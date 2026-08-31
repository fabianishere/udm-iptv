#!/usr/bin/env bash
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd -- "${here}/../.." && pwd)
sku="${1:-}"
deb="${2:-}"

if [[ -z ${sku} || -z ${deb} ]]; then
	echo "usage: $0 <sku> <deb>" >&2
	exit 1
fi

if [[ -z ${FROM_IMAGE:-} || -z ${TO_IMAGE:-} ]]; then
	echo "error: FROM_IMAGE and TO_IMAGE are required" >&2
	exit 1
fi
from_image=${FROM_IMAGE}
to_image=${TO_IMAGE}
deb=$(readlink -f "${deb}")
work=$(mktemp -d)
old_root="${work}/old"
old_deb=${OLD_PACKAGE:-"${work}/udm-iptv-old.deb"}
current_version=${CURRENT_PACKAGE_VERSION:-}
old_version=${OLD_PACKAGE_VERSION:-}
id="udm-iptv-${sku}-$$"
vol_data="${id}-data"
vol_etc_overlay="${id}-etc-overlay"
from_name="${id}-from"
to_name="${id}-to"
group_open=0
restore_lock_seconds=60
declare -A dumped_containers=()

workflow_escape() {
	local value=$1
	value=${value//%/%25}
	value=${value//$'\r'/%0D}
	value=${value//$'\n'/%0A}
	printf '%s' "${value}"
}

workflow_emit() {
	local command=$1
	local message=$2
	local escaped
	if [[ ${GITHUB_ACTIONS:-} == true ]]; then
		escaped=$(workflow_escape "${message}")
		printf '::%s::%s\n' "${command}" "${escaped}"
	fi
}

workflow_error() {
	local message=$1
	local escaped
	if [[ ${GITHUB_ACTIONS:-} == true ]]; then
		escaped=$(workflow_escape "${message}")
		printf '::error file=docker/unifi-os/test-install.sh,title=UniFi OS integration test::%s\n' \
			"${escaped}"
	fi
}

report_error() {
	local message=$1
	workflow_error "${message}"
	echo "error: ${message}" >&2
}

group_end() {
	if ((group_open)); then
		workflow_emit endgroup ""
		group_open=0
	fi
}

group_begin() {
	local title=$1
	group_end
	if [[ ${GITHUB_ACTIONS:-} == true ]]; then
		workflow_emit group "${title}"
	else
		printf '\n==> %s\n' "${title}"
	fi
	group_open=1
}

cleanup() {
	local status=$?
	local name
	trap - EXIT
	group_end
	if ((status != 0)); then
		for name in "${from_name}" "${to_name}"; do
			if docker inspect "${name}" >/dev/null 2>&1 \
				&& [[ -z ${dumped_containers[${name}]+x} ]]; then
				dump "${name}"
			fi
		done
	fi
	docker rm -f "${from_name}" "${to_name}" >/dev/null 2>&1 || true
	docker volume rm "${vol_data}" "${vol_etc_overlay}" >/dev/null 2>&1 || true
	rm -rf "${work}"
	exit "${status}"
}
trap cleanup EXIT

dump() {
	local name=$1
	local image_tag
	local label=${name}
	local status
	if [[ ${name} == "${from_name}" ]]; then
		image_tag=${from_image##*:}
		label="${sku} ${image_tag#"${sku}-"} (before upgrade)"
	elif [[ ${name} == "${to_name}" ]]; then
		image_tag=${to_image##*:}
		label="${sku} ${image_tag#"${sku}-"} (after upgrade)"
	fi
	dumped_containers["${name}"]=1
	group_begin "Diagnostics: ${label}"
	status=$(docker inspect -f '{{.State.Status}}' "${name}" 2>/dev/null) || status=gone
	echo "container status=${status}" >&2
	docker logs "${name}" >&2 || true
	docker exec "${name}" systemctl is-system-running >&2 || true
	docker exec "${name}" systemctl list-jobs --no-pager >&2 || true
	docker exec "${name}" systemctl show \
		-p Id -p ActiveState -p SubState -p Job \
		udm-iptv-test.target network.target network-online.target >&2 || true
	docker exec "${name}" systemctl status udm-iptv-restore.service udm-iptv.service >&2 || true
	docker exec "${name}" journalctl -u udm-iptv-restore -u udm-iptv --no-pager >&2 || true
	group_end
}

log_config() {
	local name=$1
	local label=$2
	printf '\n--- /etc/udm-iptv.conf (%s) ---\n' "${label}"
	docker exec "${name}" cat /etc/udm-iptv.conf
}

ensure_arm64() {
	local image=$1
	if docker run --rm --platform linux/arm64 "${image}" uname -m; then
		return 0
	fi
	docker run --privileged --rm tonistiigi/binfmt --install arm64
	docker run --rm --platform linux/arm64 "${image}" uname -m
}

assert_firmware_overlay_contract() {
	local image=$1
	local script=/usr/share/initramfs-tools/scripts/ubnt
	if ! docker run --rm --platform linux/arm64 "${image}" \
		grep -Fq 'upperdir=${MNT_RWFS}/data' "${script}"; then
		report_error "${image} does not contain the expected persistent root overlay"
		return 1
	fi
	if docker run --rm --platform linux/arm64 "${image}" \
		grep -Eq '^etc/systemd/system/?$' "${script}"; then
		report_error "${image} discards custom systemd units during a firmware update"
		return 1
	fi
	echo "firmware overlay preserves custom systemd units in ${image}"
}

boot() {
	local name=$1
	local image=$2
	local network=${3:-bridge}
	local lock_seconds=${4:-}
	docker rm -f "${name}" >/dev/null 2>&1 || true
	docker run -d --name "${name}" --platform linux/arm64 --privileged --cgroupns=host \
		--network "${network}" \
		--stop-signal SIGRTMIN+3 \
		-v /sys/fs/cgroup:/sys/fs/cgroup:rw \
		--tmpfs /run:exec --tmpfs /run/lock --tmpfs /tmp:exec \
		-v "${vol_data}:/data" \
		-v "${vol_etc_overlay}:/var/lib/udm-iptv-test/etc-overlay" \
		-v "${deb}:/tmp/udm-iptv.deb:ro" \
		-v "${old_deb}:/tmp/udm-iptv-old.deb:ro" \
		-v "${repo}/install.sh:/tmp/install.sh:ro" \
		-v "${here}/harness.sh:/harness.sh:ro" \
		-v "${here}/udm-iptv-test.target:/usr/local/lib/systemd/system/udm-iptv-test.target:ro" \
		-e DEBIAN_FRONTEND=noninteractive \
		-e UDM_IPTV_PACKAGE=/tmp/udm-iptv.deb \
		-e UDM_IPTV_TEST_LOCK_SECONDS="${lock_seconds}" \
		"${image}" \
		/harness.sh
}

wait_systemd() {
	local name=$1
	local n=0
	local status
	while ((n < 60)); do
		status=$(docker inspect -f '{{.State.Status}}' "${name}" 2>/dev/null || echo gone)
		if [[ ${status} == exited || ${status} == dead || ${status} == gone ]]; then
			report_error "${name} ${status} while waiting for the test target"
			dump "${name}"
			return 1
		fi
		if [[ ${status} == running ]] \
			&& docker exec "${name}" test -S /run/systemd/private \
			&& docker exec "${name}" systemctl is-active --quiet udm-iptv-test.target 2>/dev/null; then
			echo "test target active in ${name}"
			return 0
		fi
		if ((n % 10 == 0)); then
			workflow_emit debug "Waiting for the test target in ${name}: container=${status}, elapsed=${n}s"
		fi
		sleep 2
		((n += 2))
	done
	report_error "test target did not become active in ${name}"
	dump "${name}"
	return 1
}

wait_pkg() {
	local name=$1
	local n=0
	while ((n < 180)); do
		if docker exec "${name}" test -e /usr/bin/udm-iptv \
			&& docker exec "${name}" test -e /usr/lib/udm-iptv/udm-iptvd; then
			echo "package present in ${name}"
			return 0
		fi
		if ((n % 10 == 0)); then
			workflow_emit debug "Waiting for the restored package in ${name}: elapsed=${n}s"
		fi
		sleep 2
		((n += 2))
	done
	report_error "restore did not install the package in ${name}"
	dump "${name}"
	return 1
}

report_runtime_kernel_limitation() {
	local journal=$1
	if ! grep -Fq "IP_OPTIONS: Protocol not available" <<<"${journal}"; then
		return 1
	fi
	grep -F "IP_OPTIONS: Protocol not available" <<<"${journal}" | tail -n 1
	echo "runtime health requires a device kernel with multicast routing"
}

assert_service_runtime_boundary() {
	local name=$1
	local n=0
	local journal
	local main_pid
	local observed_main_pid
	local observed_restarts
	local restarts
	while ((n < 180)); do
		journal=$(docker exec "${name}" journalctl -b -u udm-iptv --no-pager)
		if docker exec "${name}" systemctl is-enabled --quiet udm-iptv 2>/dev/null \
			&& docker exec "${name}" test "$(docker exec "${name}" sh -c \
				'command -v improxy')" = \
				/usr/sbin/improxy \
			&& grep -Fq "Starting IGMP Proxy" <<<"${journal}"; then
			docker exec "${name}" systemctl is-enabled udm-iptv
			if docker exec "${name}" systemctl is-active --quiet udm-iptv 2>/dev/null; then
				main_pid=$(docker exec "${name}" systemctl show \
					--property MainPID --value udm-iptv)
				restarts=$(docker exec "${name}" systemctl show \
					--property NRestarts --value udm-iptv)
				sleep 10
				observed_main_pid=$(docker exec "${name}" systemctl show \
					--property MainPID --value udm-iptv)
				observed_restarts=$(docker exec "${name}" systemctl show \
					--property NRestarts --value udm-iptv)
				if ! docker exec "${name}" systemctl is-active --quiet udm-iptv 2>/dev/null \
					|| [[ ${observed_main_pid} != "${main_pid}" ]] \
					|| [[ ${observed_restarts} != "${restarts}" ]]; then
					journal=$(docker exec "${name}" \
						journalctl -b -u udm-iptv --no-pager)
					if report_runtime_kernel_limitation "${journal}"; then
						return 0
					fi
					report_error "real proxy did not remain stable in ${name}"
					dump "${name}"
					return 1
				fi
				docker exec "${name}" systemctl is-active udm-iptv
			else
				if ! report_runtime_kernel_limitation "${journal}"; then
					report_error "real proxy failed for an unexpected reason in ${name}"
					dump "${name}"
					return 1
				fi
			fi
			return 0
		fi
		if ((n % 10 == 0)); then
			workflow_emit debug "Waiting for udm-iptv in ${name}: elapsed=${n}s"
		fi
		sleep 2
		((n += 2))
	done
	report_error "udm-iptv did not reach the real proxy in ${name}"
	dump "${name}"
	return 1
}

assert_restored() {
	local name=$1
	local lock_seconds=${2:-0}
	local deadline=$((180 + lock_seconds))
	local n=0
	local restore_journal
	while ((n < deadline)); do
		restore_journal=$(docker exec "${name}" \
			journalctl -b -u udm-iptv-restore.service --no-pager)
		if grep -Fq "Finished Reinstall udm-iptv after a firmware update." \
			<<<"${restore_journal}"; then
			break
		fi
		if docker exec "${name}" systemctl is-failed --quiet \
			udm-iptv-restore.service 2>/dev/null; then
			report_error "restore service failed in ${name}"
			dump "${name}"
			return 1
		fi
		sleep 2
		((n += 2))
	done
	if ((n >= deadline)); then
		report_error "restore service did not finish in ${name}"
		dump "${name}"
		return 1
	fi
	wait_pkg "${name}"
	if [[ $(docker exec "${name}" systemctl show --property Result --value \
		udm-iptv-restore.service) != success ]]; then
		report_error "restore service did not finish successfully in ${name}"
		dump "${name}"
		return 1
	fi
	if ((lock_seconds > 0)) \
		&& ! grep -Fq "Waiting for another package manager to finish..." \
			<<<"${restore_journal}"; then
		report_error "restore did not wait for the package-manager lock in ${name}"
		dump "${name}"
		return 1
	fi
	if grep -Fq "warning: no profile at " <<<"${restore_journal}"; then
		report_error "restore emitted a missing-profile warning in ${name}"
		dump "${name}"
		return 1
	fi
	docker exec "${name}" test -e /etc/systemd/system/udm-iptv-restore.service
	docker exec "${name}" systemctl is-enabled --quiet udm-iptv-restore
	assert_service_runtime_boundary "${name}"
}

assert_version() {
	local name=$1
	local expected=$2
	local actual
	actual=$(docker exec "${name}" dpkg-query -W -f='${Version}' udm-iptv)
	if [[ ${actual} != "${expected}" ]]; then
		report_error "expected udm-iptv ${expected} in ${name}, found ${actual}"
		return 1
	fi
	echo "package version ${actual} in ${name}"
}

assert_removed() {
	local name=$1
	if docker exec "${name}" test -e /usr/bin/udm-iptv; then
		report_error "package still installed in ${name}"
		return 1
	fi
	if docker exec "${name}" test -L \
		/etc/systemd/system/multi-user.target.wants/udm-iptv-restore.service; then
		report_error "restore service still enabled in ${name}"
		return 1
	fi
}

workflow_emit notice "Testing ${sku}: ${from_image} -> ${to_image}"
echo "from=${from_image}"
echo "to=${to_image}"

group_begin "Prepare package upgrade"
if [[ -n ${OLD_PACKAGE:-} ]]; then
	old_deb=$(readlink -f "${old_deb}")
	if [[ -z ${current_version} || -z ${old_version} ]]; then
		report_error "OLD_PACKAGE requires CURRENT_PACKAGE_VERSION and OLD_PACKAGE_VERSION"
		exit 1
	fi
else
	current_version=$(dpkg-deb -f "${deb}" Version)
	old_version="${current_version}~integration"
	dpkg-deb -R "${deb}" "${old_root}"
	sed -i "s/^Version: .*/Version: ${old_version}/" "${old_root}/DEBIAN/control"
	dpkg-deb -Zxz --root-owner-group -b "${old_root}" "${old_deb}"
fi
echo "package upgrade=${old_version} -> ${current_version}"
group_end

group_begin "Prepare ARM64 images"
ensure_arm64 "${from_image}"
ensure_arm64 "${to_image}"
assert_firmware_overlay_contract "${from_image}"
assert_firmware_overlay_contract "${to_image}"
group_end

docker volume create "${vol_data}" >/dev/null
docker volume create "${vol_etc_overlay}" >/dev/null

group_begin "Install on ${from_image}"
boot "${from_name}" "${from_image}"
wait_systemd "${from_name}"
docker exec \
	-e DEBIAN_FRONTEND=noninteractive \
	-e UDM_IPTV_PACKAGE=/tmp/udm-iptv-old.deb \
	"${from_name}" \
	sh /tmp/install.sh
assert_version "${from_name}" "${old_version}"
docker exec "${from_name}" test -e /data/udm-iptv/udm-iptv.deb
docker exec "${from_name}" test -e /data/udm-iptv/debconf.preseed
docker exec "${from_name}" test -e /data/udm-iptv/udm-iptv.conf
docker exec "${from_name}" test -e /data/udm-iptv/udm-iptv-restore
docker exec "${from_name}" test ! -e /data/udm-iptv/udm-iptv-restore.service
log_config "${from_name}" "after initial installation"
docker exec "${from_name}" cp /etc/udm-iptv.conf /data/udm-iptv/udm-iptv.conf.installed
docker exec "${from_name}" cp /data/udm-iptv/debconf.preseed /data/udm-iptv/debconf.preseed.installed
docker exec "${from_name}" udm-iptv persist
log_config "${from_name}" "after repeated persistence"
docker exec "${from_name}" cmp /data/udm-iptv/debconf.preseed /data/udm-iptv/debconf.preseed.installed
assert_service_runtime_boundary "${from_name}"
log_config "${from_name}" "before package upgrade"
docker exec "${from_name}" udm-iptv upgrade --package /tmp/udm-iptv.deb
log_config "${from_name}" "after package upgrade"
assert_version "${from_name}" "${current_version}"

no_op_output=$(docker exec "${from_name}" \
	udm-iptv upgrade --version "${current_version}")
echo "${no_op_output}"
if ! grep -Fq "udm-iptv ${current_version} is already installed. Use --force to reinstall." \
	<<<"${no_op_output}"; then
	report_error "same-version upgrade did not stop early in ${from_name}"
	exit 1
fi
if grep -Eq '^(Downloading|Installing packages)' <<<"${no_op_output}"; then
	report_error "same-version upgrade downloaded or installed a package in ${from_name}"
	exit 1
fi

package_url=http://127.0.0.1:18081/udm-iptv.deb
docker exec "${from_name}" sh -c \
	'busybox httpd -f -p 127.0.0.1:18081 -h /tmp >/tmp/udm-iptv-httpd.log 2>&1 & echo $! >/tmp/udm-iptv-httpd.pid'
docker exec "${from_name}" sh -c \
	'for attempt in 1 2 3 4 5; do busybox wget -q -O /dev/null http://127.0.0.1:18081/udm-iptv.deb && exit 0; sleep 1; done; exit 1'
force_output=$(docker exec -e DEBIAN_FRONTEND=noninteractive "${from_name}" \
	udm-iptv upgrade --force --package "${package_url}")
docker exec "${from_name}" sh -c 'kill "$(cat /tmp/udm-iptv-httpd.pid)"'
echo "${force_output}"
if ! grep -Fq "Downloading ${package_url}..." <<<"${force_output}" \
	|| ! grep -Fq 'Installing packages...' <<<"${force_output}" \
	|| grep -Fq 'is already installed' <<<"${force_output}"; then
	report_error "forced same-version upgrade did not download and reinstall in ${from_name}"
	exit 1
fi

reconfigure_output=$(docker exec -e DEBIAN_FRONTEND=noninteractive "${from_name}" \
	udm-iptv reconfigure 2>&1)
echo "${reconfigure_output}"
saved_count=$(grep -Ec '^Saved [0-9]+ answers to /data/udm-iptv\.$' \
	<<<"${reconfigure_output}")
if [[ ${saved_count} -ne 1 ]]; then
	report_error "reconfigure did not save answers exactly once in ${from_name}"
	exit 1
fi

docker exec "${from_name}" cmp /tmp/udm-iptv.deb /data/udm-iptv/udm-iptv.deb
docker exec "${from_name}" cmp /etc/udm-iptv.conf /data/udm-iptv/udm-iptv.conf.installed
docker exec "${from_name}" cmp /data/udm-iptv/debconf.preseed /data/udm-iptv/debconf.preseed.installed
docker exec "${from_name}" systemctl is-enabled --quiet udm-iptv-restore.service
assert_service_runtime_boundary "${from_name}"
docker stop "${from_name}"
group_end

group_begin "Restore across extracted rootfs swap to ${to_image}"
boot "${to_name}" "${to_image}" none "${restore_lock_seconds}"
wait_systemd "${to_name}"
if [[ $(docker inspect -f '{{.HostConfig.NetworkMode}}' "${to_name}") != none ]]; then
	report_error "restore container still has Docker networking"
	exit 1
fi
if docker exec "${to_name}" test -e /usr/lib/udm-iptv/udm-iptvd; then
	report_error "package still on /usr after firmware swap"
	exit 1
fi
assert_restored "${to_name}" "${restore_lock_seconds}"
docker exec "${to_name}" test ! -e /data/udm-iptv/udm-iptv-restore.service
docker exec "${to_name}" cmp /etc/udm-iptv.conf /data/udm-iptv/udm-iptv.conf.installed
group_end

group_begin "Verify the restored installation after rebooting ${to_image}"
docker stop "${to_name}"
docker start "${to_name}"
wait_systemd "${to_name}"
wait_pkg "${to_name}"
assert_version "${to_name}" "${current_version}"
docker exec "${to_name}" cmp /etc/udm-iptv.conf /data/udm-iptv/udm-iptv.conf.installed
assert_service_runtime_boundary "${to_name}"
echo "upgrade and reboot ok"
group_end

group_begin "Remove while retaining saved state"
docker exec "${to_name}" udm-iptv uninstall --keep-data
assert_removed "${to_name}"
docker exec "${to_name}" test -e /etc/udm-iptv.conf
docker exec "${to_name}" test -e /data/udm-iptv/udm-iptv.deb
docker exec "${to_name}" test -e /data/udm-iptv/udm-iptv-restore
docker stop "${to_name}"
docker start "${to_name}"
wait_systemd "${to_name}"
assert_removed "${to_name}"
echo "removed package stayed removed after reboot"
group_end

group_begin "Restore manually, then purge"
docker exec "${to_name}" /data/udm-iptv/udm-iptv-restore
wait_pkg "${to_name}"
assert_version "${to_name}" "${current_version}"
docker exec "${to_name}" cmp /etc/udm-iptv.conf /data/udm-iptv/udm-iptv.conf.installed
assert_service_runtime_boundary "${to_name}"
docker exec "${to_name}" udm-iptv uninstall
assert_removed "${to_name}"
docker exec "${to_name}" test ! -e /etc/udm-iptv.conf
docker exec "${to_name}" test ! -e /etc/systemd/system/udm-iptv-restore.service
docker exec "${to_name}" test ! -e /data/udm-iptv
docker stop "${to_name}"
docker start "${to_name}"
wait_systemd "${to_name}"
assert_removed "${to_name}"
docker exec "${to_name}" test ! -e /data/udm-iptv
echo "purged package stayed removed after reboot"
group_end
