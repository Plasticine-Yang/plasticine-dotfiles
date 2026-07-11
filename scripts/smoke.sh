#!/bin/sh

set -eu

os_name="$(go env GOOS)"
arch_name="$(go env GOARCH)"
binary="${PLASTICINE_BINARY:-$(pwd)/dist/plasticine_${os_name}_${arch_name}}"

if [ ! -x "$binary" ]; then
	printf '%s\n' "smoke binary is not executable: $binary" >&2
	exit 1
fi

home="$(mktemp -d)"
cleanup() {
	rm -rf "$home"
}
trap cleanup EXIT HUP INT TERM

"$binary" version | grep 'plasticine ' >/dev/null
plan_output="$(PLASTICINE_WORKSTATION_ROOT="$home/workstation" "$binary" plan --home "$home" --exclude github-ssh)"
printf '%s\n' "$plan_output" | grep '^desired_state: [0-9a-f][0-9a-f]*$' >/dev/null
if [ -e "$home/state/reconciliation.json" ]; then
	printf '%s\n' "plan wrote state in smoke home" >&2
	exit 1
fi
PLASTICINE_WORKSTATION_ROOT="$home/workstation" "$binary" apply --home "$home" --exclude github-ssh --yes >/dev/null
test -f "$home/state/reconciliation.json"
PLASTICINE_WORKSTATION_ROOT="$home/workstation" "$binary" doctor --home "$home" >/dev/null
