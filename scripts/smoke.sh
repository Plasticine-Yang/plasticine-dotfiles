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

version_output="$("$binary" version)"
if [ "${PLASTICINE_EXPECT_VERSION:-}" ] || [ "${PLASTICINE_EXPECT_COMMIT:-}" ] || [ "${PLASTICINE_EXPECT_COMMIT_TIME:-}" ]; then
        if [ -z "${PLASTICINE_EXPECT_VERSION:-}" ] || [ -z "${PLASTICINE_EXPECT_COMMIT:-}" ] || [ -z "${PLASTICINE_EXPECT_COMMIT_TIME:-}" ]; then
                printf '%s\n' "all expected version metadata fields are required" >&2
                exit 1
        fi
        expected_version_output="plasticine $PLASTICINE_EXPECT_VERSION commit=$PLASTICINE_EXPECT_COMMIT commit_time=$PLASTICINE_EXPECT_COMMIT_TIME"
        if [ "$version_output" != "$expected_version_output" ]; then
                printf '%s\n' "version output mismatch" >&2
                printf '%s\n' "expected: $expected_version_output" >&2
                printf '%s\n' "actual:   $version_output" >&2
                exit 1
        fi
else
        printf '%s\n' "$version_output" | grep 'plasticine ' >/dev/null
fi
plan_output="$(PLASTICINE_WORKSTATION_ROOT="$home/workstation" "$binary" plan --home "$home" --exclude shell --exclude github-ssh --exclude neovim --exclude lazygit --exclude fnm --exclude uv --exclude zellij --exclude traex-session-manager)"
printf '%s\n' "$plan_output" | grep '^desired_state: [0-9a-f][0-9a-f]*$' >/dev/null
if [ -e "$home/state/reconciliation.json" ]; then
	printf '%s\n' "plan wrote state in smoke home" >&2
	exit 1
fi
PLASTICINE_WORKSTATION_ROOT="$home/workstation" "$binary" apply --home "$home" --exclude shell --exclude github-ssh --exclude neovim --exclude lazygit --exclude fnm --exclude uv --exclude zellij --exclude traex-session-manager --yes >/dev/null
test -f "$home/state/reconciliation.json"
PLASTICINE_WORKSTATION_ROOT="$home/workstation" "$binary" doctor --home "$home" >/dev/null
