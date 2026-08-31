#!/bin/sh
set -eu

export container=docker

test_target=udm-iptv-test.target
etc_lower=/run/udm-iptv-test/etc-lower
etc_overlay=/var/lib/udm-iptv-test/etc-overlay

# UniFi OS keeps a writable overlay across ordinary boots and firmware updates.
# Reuse only that overlay between the extracted roots so the new firmware still
# supplies its own /etc while package-created files survive naturally.
mkdir -p "${etc_lower}" "${etc_overlay}/upper" "${etc_overlay}/work"
mount --bind /etc "${etc_lower}"
mount --bind -o remount,ro "${etc_lower}"
mount -t overlay overlay \
	-o "lowerdir=${etc_lower},upperdir=${etc_overlay}/upper,workdir=${etc_overlay}/work" \
	/etc

printf 'APT::Get::Assume-Yes "true";\n' >/etc/apt/apt.conf.d/99yes

if unifi_os=$(command -v unifi-os); then
	mv "${unifi_os}" /usr/sbin/unifi-os.real
fi

for iface in br0 eth0 eth1 eth2 eth3 eth4 eth8 eth9 eth18 eth19; do
	ip link add "${iface}" type dummy 2>/dev/null || true
	ip link set "${iface}" up 2>/dev/null || true
done
ip address replace 192.0.2.1/24 dev br0

# The default profile creates its VLAN interface during service startup. Give
# both sides test-net addresses so the real proxy validates and runs.
(
	while true; do
		if ip link show iptv >/dev/null 2>&1; then
			ip address replace 198.51.100.2/24 dev iptv 2>/dev/null || true
		fi
		sleep 1
	done
) &

if [ -n "${UDM_IPTV_TEST_LOCK_SECONDS:-}" ]; then
	(
		exec 9>/var/lib/dpkg/lock
		sleep "${UDM_IPTV_TEST_LOCK_SECONDS}"
	) &
fi

# The extracted root cannot reach the hardware-dependent multi-user target.
# Pull persistent multi-user units into the small test target without naming,
# copying, enabling or starting any package unit on its behalf. Broken links
# identify units removed with the package; intact firmware units below /lib are
# deliberately left to the hardware-dependent production target.
mkdir -p "/run/systemd/system/${test_target}.wants"
for enabled in /etc/systemd/system/multi-user.target.wants/*; do
	[ -L "${enabled}" ] || continue
	name=$(basename "${enabled}")
	firmware_link="${etc_lower}/systemd/system/multi-user.target.wants/${name}"
	if [ -e "${firmware_link}" ] || [ -L "${firmware_link}" ]; then
		continue
	fi
	target=$(readlink -f "${enabled}")
	if [ -e "${enabled}" ]; then
		case ${target} in
			/etc/systemd/system/*) ;;
			*) continue ;;
		esac
	fi
	ln -sf "${target}" "/run/systemd/system/${test_target}.wants/${name}"
done

if [ -x /lib/systemd/systemd ]; then
	exec /lib/systemd/systemd --system --unit="${test_target}"
fi
if [ -x /sbin/init ]; then
	exec /sbin/init --unit="${test_target}"
fi

echo "error: no systemd in this image" >&2
exit 1
