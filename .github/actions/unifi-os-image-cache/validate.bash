#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${MODEL:?MODEL is required}"
: "${UNIFI_OS_FIRMWARES:?UNIFI_OS_FIRMWARES is required}"
: "${UNIFI_OS_IMAGE:?UNIFI_OS_IMAGE is required}"

cache_needed=false
firmwares=$(jq -er '.[] | [.board, .version, .url, .sha256] | @tsv' \
	<<<"${UNIFI_OS_FIRMWARES}")
while IFS=$'\t' read -r board version url checksum; do
	image="${UNIFI_OS_IMAGE}:${MODEL}-${version}"
	expected=$(printf '%s\t%s\t%s\t%s\t%s\n' \
		"${MODEL}" "${board}" "${version}" "${url}" "${checksum}" \
		| sha256sum | cut -d ' ' -f 1)
	actual=
	actual=$(docker image inspect --format '{{ index .Config.Labels "io.github.udm-iptv.catalog-fingerprint" }}' \
		"${image}" 2>/dev/null) || actual=
	if [[ ${actual} == "${expected}" ]]; then
		docker tag "${image}" "${UNIFI_OS_IMAGE}:${MODEL}-${board}-${version}"
		echo "Using validated ${image}"
	else
		echo "Image ${image} is unavailable or does not match the firmware matrix"
		cache_needed=true
	fi
done <<<"${firmwares}"

echo "cache-needed=${cache_needed}" >>"${GITHUB_OUTPUT}"
