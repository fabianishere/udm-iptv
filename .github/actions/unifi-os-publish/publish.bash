#!/usr/bin/env bash
set -euo pipefail

: "${MODEL:?MODEL is required}"
: "${UNIFI_OS_FIRMWARES:?UNIFI_OS_FIRMWARES is required}"
: "${UNIFI_OS_IMAGE:?UNIFI_OS_IMAGE is required}"

firmwares=$(jq -er '.[] | [.board, .version] | @tsv' \
	<<<"${UNIFI_OS_FIRMWARES}")
while IFS=$'\t' read -r board version; do
	docker push "${UNIFI_OS_IMAGE}:${MODEL}-${version}"
	docker push "${UNIFI_OS_IMAGE}:${MODEL}-${board}-${version}"
done <<<"${firmwares}"

package=${UNIFI_OS_IMAGE#ghcr.io/}
user_package=${package#*/}
visibility=$(gh api "/user/packages/container/${user_package}" --jq .visibility)
echo "visibility=${visibility}"
if [[ ${visibility} != private ]]; then
	gh api --method POST "/user/packages/container/${user_package}/visibility" \
		-f visibility=private
	visibility=$(gh api "/user/packages/container/${user_package}" --jq .visibility)
	echo "visibility=${visibility}"
fi
if [[ ${visibility} != private ]]; then
	echo "error: package ${UNIFI_OS_IMAGE} is ${visibility}, deleting it" >&2
	gh api --method DELETE "/user/packages/container/${user_package}"
	exit 1
fi
