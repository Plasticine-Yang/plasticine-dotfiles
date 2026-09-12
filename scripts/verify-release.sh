#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
asset_dir=${1:-}
revision=${2:-}
repo_url=${3:-$repo_dir}
chezmoi_bin=${CHEZMOI_BIN:-}

[ -n "$asset_dir" ] && [ -n "$revision" ] || {
    printf '%s\n' 'usage: scripts/verify-release.sh <asset-directory> <full-commit-id> [repository-url]' >&2
    exit 2
}
case $revision in
    *[!0-9a-f]*|'')
        printf '%s\n' 'release revision must be a full 40-character lowercase commit ID' >&2
        exit 2
        ;;
esac
[ "${#revision}" -eq 40 ] || {
    printf '%s\n' 'release revision must be a full 40-character commit ID' >&2
    exit 2
}
[ -n "$chezmoi_bin" ] || chezmoi_bin=$(command -v chezmoi)

[ -f "$asset_dir/install.sh" ] && [ -x "$asset_dir/install.sh" ] || {
    printf '%s\n' 'release install.sh is missing or not executable' >&2
    exit 1
}
[ -f "$asset_dir/SHA256SUMS" ] || {
    printf '%s\n' 'release SHA256SUMS is missing' >&2
    exit 1
}
[ "$(find "$asset_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 2 ] || {
    printf '%s\n' 'release directory must contain exactly install.sh and SHA256SUMS' >&2
    exit 1
}

/bin/sh -n "$asset_dir/install.sh"
grep -Fqx "readonly_repo_revision='$revision'" "$asset_dir/install.sh" || {
    printf '%s\n' 'release installer does not pin the expected revision' >&2
    exit 1
}
if grep -Fqx "readonly_repo_revision=''" "$asset_dir/install.sh"; then
    printf '%s\n' 'release installer still contains the development revision' >&2
    exit 1
fi
(cd "$asset_dir" && shasum -a 256 -c SHA256SUMS)

test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-release-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
mkdir -p "$test_root/home"
HOME=$test_root/home \
PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
PLASTICINE_DOTFILES_REPO_URL=$repo_url \
PLASTICINE_CHEZMOI_SOURCE_DIR=$test_root/source \
PLASTICINE_CHEZMOI_CONFIG_FILE=$test_root/config/chezmoi.toml \
PLASTICINE_CHEZMOI_STATE_FILE=$test_root/config/chezmoistate.boltdb \
PLASTICINE_CHEZMOI_DEST_DIR=$test_root/home \
    "$asset_dir/install.sh" -y >/dev/null

actual_revision=$(git -C "$test_root/source" rev-parse HEAD)
[ "$actual_revision" = "$revision" ] || {
    printf 'release installer selected %s instead of %s\n' "$actual_revision" "$revision" >&2
    exit 1
}
[ "$(git -C "$test_root/source" symbolic-ref -q HEAD || true)" = '' ] || {
    printf '%s\n' 'release installer did not leave the source at a detached revision' >&2
    exit 1
}

printf 'release assets verified for %s\n' "$revision"
