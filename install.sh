#!/bin/sh
# Installation script for the udm-iptv service
#
# Copyright (C) 2022 Fabian Mastenbroek.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.

set -e

if command -v unifi-os >/dev/null 2>&1; then
	echo "error: You need to be in UniFi OS to run the installer."
	echo "Please run the following command to enter UniFi OS:"
	echo
	printf "\t unifi-os shell\n"
	exit 1
fi

UDM_IPTV_VERSION="${UDM_IPTV_VERSION:-3.0.6}"
UDM_IPTV_REPOSITORY="${UDM_IPTV_REPOSITORY:-fabianishere/udm-iptv}"
UDM_IPTV_STATE_DIR="${UDM_IPTV_STATE_DIR:-/data/udm-iptv}"
UDM_IPTV_RUN="${UDM_IPTV_RUN:-}"
UDM_IPTV_PR="${UDM_IPTV_PR:-}"
UDM_IPTV_TOKEN="${UDM_IPTV_TOKEN:-${GITHUB_TOKEN:-}}"
UDM_IPTV_TIMEOUT_SECONDS="${UDM_IPTV_TIMEOUT_SECONDS:-900}"
UDM_IPTV_FORCE="${UDM_IPTV_FORCE:-false}"

case "${UDM_IPTV_PR}" in
	*/*\#*)
		UDM_IPTV_REPOSITORY="${UDM_IPTV_PR%\#*}"
		UDM_IPTV_PR="${UDM_IPTV_PR##*\#}"
		;;
	*) ;;
esac

api="https://api.github.com/repos/${UDM_IPTV_REPOSITORY}"

# Puts the response in api_body and the exit status of curl in api_status. An
# empty body means a failed request or an answer without the wanted field, which
# api_status tells apart.
api_fetch() {
	api_status=0
	if [ -n "${UDM_IPTV_TOKEN}" ]; then
		api_body=$(curl -fsSL -H "Authorization: Bearer ${UDM_IPTV_TOKEN}" "$@") || api_status=$?
	else
		api_body=$(curl -fsSL "$@") || api_status=$?
	fi
}

# Every caller treats an empty answer as a failure, so a failed request yields
# nothing instead of aborting the script.
api_get() {
	api_fetch "$@"
	printf '%s\n' "${api_body}"
}

json_field() {
	sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" | head -n 1
}

skip_installed=false
check_installed_version() {
	version=$1
	skip_installed=false
	[ "${UDM_IPTV_FORCE}" != true ] || return 0
	installed=$(dpkg-query -W -f='${Version}' udm-iptv 2>/dev/null) || installed=
	if [ "${installed}" = "${version}" ]; then
		echo "udm-iptv ${version} is already installed. Use --force to reinstall."
		skip_installed=true
	fi
}

resolve_head() {
	api_get "${api}/pulls/${UDM_IPTV_PR}" | json_field sha
}

resolve_run() {
	if [ -n "${UDM_IPTV_PR}" ]; then
		api_get "${api}/actions/workflows/build.yml/runs?head_sha=$1&event=pull_request&per_page=1" | json_field id
	elif [ "${UDM_IPTV_RUN}" = "latest" ]; then
		api_get "${api}/actions/runs?status=success&per_page=1" | json_field id
	else
		echo "${UDM_IPTV_RUN}"
	fi
}

await_run() {
	waited=0
	while [ "${waited}" -lt "${UDM_IPTV_TIMEOUT_SECONDS}" ]; do
		# A failed request is retried, since only an answered request tells us
		# whether the run exists.
		api_fetch "${api}/actions/runs/$1"
		if [ "${api_status}" -eq 0 ]; then
			status=$(printf '%s\n' "${api_body}" | json_field status)
			case "${status}" in
				completed) return 0 ;;
				"")
					echo "error: Workflow run $1 not found in ${UDM_IPTV_REPOSITORY}."
					return 1
					;;
				*) echo "Waiting for run $1 to complete (${status})..." ;;
			esac
		else
			echo "Waiting for the API to answer about run $1..."
		fi
		sleep 15
		waited=$((waited + 15))
	done
	echo "error: Run $1 did not complete within ${UDM_IPTV_TIMEOUT_SECONDS}s."
	return 1
}

dest=
cleanup() {
	if [ -n "${dest}" ]; then
		rm -rf "${dest}"
	fi
}
trap cleanup EXIT

dest=$(mktemp -d)

if [ -n "${UDM_IPTV_RUN}" ] || [ -n "${UDM_IPTV_PR}" ]; then
	if [ -n "${UDM_IPTV_PR}" ]; then
		head=$(resolve_head)
		[ -n "${head}" ] || {
			echo "error: Pull request ${UDM_IPTV_PR} not found in ${UDM_IPTV_REPOSITORY}."
			exit 1
		}
		echo "Pull request ${UDM_IPTV_PR} is at ${head}."
		run=$(resolve_run "${head}")
	else
		run=$(resolve_run)
	fi

	[ -n "${run}" ] || {
		echo "error: No workflow run found in ${UDM_IPTV_REPOSITORY}."
		exit 1
	}

	await_run "${run}"

	api_fetch "${api}/actions/runs/${run}"
	[ "${api_status}" -eq 0 ] || {
		echo "error: Could not read the result of run ${run}."
		exit 1
	}
	conclusion=$(printf '%s\n' "${api_body}" | json_field conclusion)
	[ "${conclusion}" = "success" ] || {
		echo "error: Run ${run} concluded ${conclusion}."
		exit 1
	}

	artifacts=$(api_get "${api}/actions/runs/${run}/artifacts?name=build-artifacts")
	zip=$(printf '%s\n' "${artifacts}" | json_field archive_download_url)
	[ -n "${zip}" ] || {
		echo "error: Run ${run} has no build-artifacts artifact."
		exit 1
	}

	expired=$(printf '%s\n' "${artifacts}" | json_field expired)
	[ "${expired}" != "true" ] || {
		echo "error: The artifact of run ${run} has expired."
		exit 1
	}

	if [ -z "${UDM_IPTV_TOKEN}" ]; then
		echo "error: Downloading a workflow artifact requires a token."
		echo "Set UDM_IPTV_TOKEN to a personal access token with 'actions:read',"
		echo "or install from a release instead."
		exit 1
	fi

	echo "Downloading artifact of run ${run}..."
	curl -fsSL -H "Authorization: Bearer ${UDM_IPTV_TOKEN}" -o "${dest}/artifact.zip" "${zip}"
	busybox unzip -o -q -d "${dest}" "${dest}/artifact.zip"

	deb=$(find "${dest}" -name '*.deb' | head -n 1)
	[ -n "${deb}" ] || {
		echo "error: No package found in the artifact of run ${run}."
		exit 1
	}
	mv "${deb}" "${dest}/udm-iptv.deb"
else
	if [ -z "${UDM_IPTV_PACKAGE:-}" ] && [ "${UDM_IPTV_VERSION}" = "latest" ]; then
		latest_tag=$(api_get "${api}/releases/latest" | json_field tag_name)
		[ -n "${latest_tag}" ] || {
			echo "error: Could not resolve the latest release of ${UDM_IPTV_REPOSITORY}."
			exit 1
		}
		UDM_IPTV_VERSION=${latest_tag#v}
		echo "Latest release is ${latest_tag}."
	fi
	if [ -z "${UDM_IPTV_PACKAGE:-}" ]; then
		check_installed_version "${UDM_IPTV_VERSION}"
		[ "${skip_installed}" != true ] || exit 0
	fi

	UDM_IPTV_PACKAGE="${UDM_IPTV_PACKAGE:-https://github.com/${UDM_IPTV_REPOSITORY}/releases/download/v${UDM_IPTV_VERSION}/udm-iptv_${UDM_IPTV_VERSION}_all.deb}"

	case "${UDM_IPTV_PACKAGE}" in
		http://* | https://*)
			echo "Downloading ${UDM_IPTV_PACKAGE}..."
			curl -fsSL -o "${dest}/udm-iptv.deb" "${UDM_IPTV_PACKAGE}"
			;;
		*)
			echo "Using ${UDM_IPTV_PACKAGE}..."
			cp "${UDM_IPTV_PACKAGE}" "${dest}/udm-iptv.deb"
			;;
	esac
fi

package_version=$(dpkg-deb -f "${dest}/udm-iptv.deb" Version)
check_installed_version "${package_version}"
[ "${skip_installed}" != true ] || exit 0

# Fix permissions on the packages
chown _apt:root "${dest}/udm-iptv.deb"

echo "Installing packages..."

# Update APT sources (best effort)
apt-get update >/dev/null || true

# Install dialog package for interactive install
apt-get install -q -y dialog >/dev/null || echo "Failed to install dialog... Using readline frontend"

# Install udm-iptv
if [ "${UDM_IPTV_FORCE}" = true ]; then
	apt-get install --reinstall -o Acquire::AllowUnsizedPackages=1 -q "${dest}/udm-iptv.deb"
else
	apt-get install -o Acquire::AllowUnsizedPackages=1 -q "${dest}/udm-iptv.deb"
fi

# Keep the package next to the saved answers so that a firmware update can be
# recovered from without network access
if [ -d "$(dirname "${UDM_IPTV_STATE_DIR}")" ]; then
	mkdir -p "${UDM_IPTV_STATE_DIR}"
	cp "${dest}/udm-iptv.deb" "${UDM_IPTV_STATE_DIR}/udm-iptv.deb"
fi

echo "Installation successful... You can find your configuration at /etc/udm-iptv.conf."
echo
echo "Use the following command to reconfigure the script:"
echo
printf "\t udm-iptv reconfigure\n"
