#!/usr/bin/env bash
set -euo pipefail

: "${SKU:?SKU is required}"
: "${UNIFI_OS_IMAGE:?UNIFI_OS_IMAGE is required}"

case ${SKU} in
	all | udm | udmbeast | udmpro | udmpromax | udmse) ;;
	*)
		echo "error: unknown sku ${SKU}" >&2
		exit 1
		;;
esac

cutoff=${CUTOFF:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
response=$(curl -fsSL --retry 3 --retry-max-time 45 \
	--connect-timeout 10 --max-time 30 \
	--get https://fw-update.ui.com/api/firmware \
	--data-urlencode 'filter=eq~~product~~unifi-dream' \
	--data-urlencode 'filter=eq~~channel~~release' \
	--data-urlencode 'sort=-created' \
	--data-urlencode 'limit=1000')

matrix=$(jq -cer \
	--arg cutoff "${cutoff}" \
	--arg wanted "${SKU}" \
	--arg image "${UNIFI_OS_IMAGE}" '
		($cutoff | fromdateiso8601) as $cutoff_epoch |
		._embedded.firmware as $firmware |
		[
			{"model": "udm", "platform": "UDM"},
			{"model": "udmbeast", "platform": "UDMEA4C"},
			{"model": "udmpro", "platform": "UDMPRO"},
			{"model": "udmpromax", "platform": "UDMPROMAX"},
			{"model": "udmse", "platform": "UDMPROSE"}
		] |
		[
			.[] |
			select($wanted == "all" or .model == $wanted) |
			. as $device |
			[
				$firmware[] |
				select(.platform == $device.platform) |
				select((.created | fromdateiso8601) < $cutoff_epoch) |
				. + {version_number: (.version | ltrimstr("v") | split("+")[0])}
			] |
			group_by(.version_number) |
			map(max_by(.created)) |
			sort_by(.created) |
			if length < 2 then
				error("fewer than two releases before " + $cutoff + " for " + $device.model)
			else
				(.[-2:] | map({
					board: $device.platform,
					version: .version_number,
					url: ._links.data.href,
					sha256: .sha256_checksum
				})) as $pair |
				{
					model: $device.model,
					firmwares: $pair,
					from_image: ($image + ":" + $device.model + "-" + $pair[0].version),
					to_image: ($image + ":" + $device.model + "-" + $pair[1].version)
				}
			end
		]
	' <<<"${response}")

echo "Firmware cutoff: ${cutoff}" >&2
printf '%s\n' "${matrix}"
