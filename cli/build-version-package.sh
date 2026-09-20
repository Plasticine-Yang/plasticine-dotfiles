#!/bin/sh
set -eu

error() {
    printf 'build-version-package: %s\n' "$1" >&2
}

if [ "$#" -ne 4 ]; then
    error 'usage: build-version-package.sh <version> <release-installer> <self-update-executable> <output-directory>'
    exit 2
fi

release_version=$1
installer=$2
updater=$3
output_dir=$4

if ! printf '%s\n' "$release_version" |
    LC_ALL=C grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    error 'version must be a stable vMAJOR.MINOR.PATCH release.'
    exit 2
fi
[ -f "$installer" ] && [ ! -L "$installer" ] && [ -x "$installer" ] || {
    error 'release installer must be an executable regular file.'
    exit 1
}
[ -f "$updater" ] && [ ! -L "$updater" ] && [ -x "$updater" ] || {
    error 'self-update module must be an executable regular file.'
    exit 1
}
[ ! -e "$output_dir" ] && [ ! -L "$output_dir" ] || {
    error "output already exists: $output_dir"
    exit 1
}
grep -Fqx "readonly_release_version='$release_version'" "$installer" || {
    error 'installer does not contain the requested immutable release version.'
    exit 1
}
if grep -Fqx "readonly_repo_revision=''" "$installer" ||
    ! LC_ALL=C grep -Eq "^readonly_repo_revision='[0-9a-f]{40}'$" "$installer"; then
    error 'installer does not contain an immutable release revision.'
    exit 1
fi
for digest_name in readonly_source_sha256 readonly_plugins_sha256; do
    LC_ALL=C grep -Eq "^${digest_name}='[0-9a-f]{64}'$" "$installer" || {
        error "installer does not contain immutable ${digest_name#readonly_} metadata."
        exit 1
    }
done

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
package_cli=$script_dir/version-package/plasticine
[ -f "$package_cli" ] && [ -x "$package_cli" ] || {
    error 'version-package CLI source is unavailable.'
    exit 1
}

output_parent=${output_dir%/*}
[ "$output_parent" != "$output_dir" ] || output_parent=.
mkdir -p "$output_parent"
[ -d "$output_parent" ] && [ ! -L "$output_parent" ] || {
    error 'output parent must be a real directory.'
    exit 1
}
stage_dir=$(mktemp -d "$output_parent/.plasticine-package.XXXXXX")
cleanup() { rm -rf "$stage_dir"; }
trap cleanup EXIT HUP INT TERM

cp "$package_cli" "$stage_dir/plasticine"
cp "$installer" "$stage_dir/install.sh"
cp "$updater" "$stage_dir/self-update"
printf '%s\n' "$release_version" >"$stage_dir/VERSION"
chmod 755 "$stage_dir/plasticine" "$stage_dir/install.sh" "$stage_dir/self-update"
chmod 644 "$stage_dir/VERSION"
mv "$stage_dir" "$output_dir"
trap - EXIT HUP INT TERM
