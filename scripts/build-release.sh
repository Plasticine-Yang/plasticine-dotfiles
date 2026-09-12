#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
revision=${1:-}
output_dir=${2:-$repo_dir/dist}

case $revision in
    *[!0-9a-f]*|'')
        printf '%s\n' 'usage: scripts/build-release.sh <full-commit-id> [output-directory]' >&2
        exit 2
        ;;
    *) ;;
esac
[ "${#revision}" -eq 40 ] || {
    printf '%s\n' 'release revision must be a full 40-character lowercase commit ID' >&2
    exit 2
}

[ ! -e "$output_dir" ] || {
    printf 'release output already exists: %s\n' "$output_dir" >&2
    exit 1
}
mkdir -p "$output_dir"

awk -v revision="$revision" '
    /^readonly_repo_revision=\x27\x27$/ {
        print "readonly_repo_revision=\x27" revision "\x27"
        replaced++
        next
    }
    { print }
    END { if (replaced != 1) exit 1 }
' "$repo_dir/install.sh" > "$output_dir/install.sh" || {
    printf '%s\n' 'failed to render the release revision into install.sh' >&2
    exit 1
}
chmod 755 "$output_dir/install.sh"

(
    cd "$output_dir"
    shasum -a 256 install.sh > SHA256SUMS
)

printf 'built release assets for %s in %s\n' "$revision" "$output_dir"
