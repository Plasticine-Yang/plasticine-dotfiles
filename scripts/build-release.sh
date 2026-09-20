#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
revision=${1:-}
output_dir=${2:-$repo_dir/dist}
release_version=${3:-}
source_repository=${4:-$repo_dir}

case $revision in
    *[!0-9a-f]*|'')
        printf '%s\n' 'usage: scripts/build-release.sh <full-commit-id> [output-directory] <release-version> [source-repository]' >&2
        exit 2
        ;;
    *) ;;
esac
[ "${#revision}" -eq 40 ] || {
    printf '%s\n' 'release revision must be a full 40-character lowercase commit ID' >&2
    exit 2
}
if ! printf '%s\n' "$release_version" |
    LC_ALL=C grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    printf '%s\n' 'release version must be a stable vMAJOR.MINOR.PATCH tag' >&2
    exit 2
fi
git -C "$source_repository" cat-file -e "$revision^{commit}" 2>/dev/null || {
    printf '%s\n' 'release revision is unavailable from the source repository' >&2
    exit 1
}

[ ! -e "$output_dir" ] || {
    printf 'release output already exists: %s\n' "$output_dir" >&2
    exit 1
}
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd -P)

release_bundle_repo=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-release-bundle.XXXXXX")
trap 'rm -rf "$release_bundle_repo"' EXIT HUP INT TERM
git init -q --bare "$release_bundle_repo"
git -C "$release_bundle_repo" symbolic-ref HEAD refs/heads/plasticine-release
git -C "$release_bundle_repo" fetch -q --no-tags "$source_repository" \
    "$revision:refs/heads/plasticine-release"
git -C "$release_bundle_repo" bundle create "$output_dir/plasticine-source.bundle" --all
rm -rf "$release_bundle_repo"
trap - EXIT HUP INT TERM
if [ -n "${PLASTICINE_MANAGED_PLUGINS_ASSET:-}" ]; then
    [ -f "$PLASTICINE_MANAGED_PLUGINS_ASSET" ] && [ ! -L "$PLASTICINE_MANAGED_PLUGINS_ASSET" ] || {
        printf '%s\n' 'PLASTICINE_MANAGED_PLUGINS_ASSET is not a regular file' >&2
        exit 1
    }
    cp "$PLASTICINE_MANAGED_PLUGINS_ASSET" "$output_dir/plasticine-managed-plugins.tar.gz"
else
    "$repo_dir/scripts/build-managed-plugins.sh" "$repo_dir/release/managed-plugins.tsv" \
        "$output_dir/plasticine-managed-plugins.tar.gz"
fi
source_sha256=$(shasum -a 256 "$output_dir/plasticine-source.bundle" | awk '{print $1}')
plugins_sha256=$(shasum -a 256 "$output_dir/plasticine-managed-plugins.tar.gz" | awk '{print $1}')

rendered_installer=$output_dir/.install.sh.rendered
awk -v revision="$revision" -v version="$release_version" \
    -v source_sha256="$source_sha256" -v plugins_sha256="$plugins_sha256" '
    /^readonly_repo_revision=\x27\x27$/ {
        print "readonly_repo_revision=\x27" revision "\x27"
        replaced++
        next
    }
    /^readonly_release_version=\x27\x27$/ { print "readonly_release_version=\x27" version "\x27"; version_replaced++; next }
    /^readonly_source_sha256=\x27\x27$/ { print "readonly_source_sha256=\x27" source_sha256 "\x27"; source_replaced++; next }
    /^readonly_plugins_sha256=\x27\x27$/ { print "readonly_plugins_sha256=\x27" plugins_sha256 "\x27"; plugins_replaced++; next }
    { print }
    END { if (replaced != 1 || version_replaced != 1 || source_replaced != 1 || plugins_replaced != 1) exit 1 }
' "$repo_dir/install.sh" > "$rendered_installer" || {
    printf '%s\n' 'failed to render the release revision into install.sh' >&2
    exit 1
}
awk -v chezmoi_module="$repo_dir/lib/chezmoi-bootstrap.sh" \
    -v release_module="$repo_dir/lib/release-payload.sh" '
    /^\[ -f .*lib\/chezmoi-bootstrap\.sh/ {
        while ((getline line < chezmoi_module) > 0) print line
        close(chezmoi_module)
        getline
        getline
        chezmoi_replaced++
        next
    }
    /^\[ -f .*lib\/release-payload\.sh/ {
        while ((getline line < release_module) > 0) print line
        close(release_module)
        getline
        getline
        release_replaced++
        next
    }
    { print }
    END { if (chezmoi_replaced != 1 || release_replaced != 1) exit 1 }
' "$rendered_installer" > "$output_dir/install.sh" || {
    printf '%s\n' 'failed to inline the chezmoi bootstrap into release install.sh' >&2
    exit 1
}
rm -f "$rendered_installer"
chmod 755 "$output_dir/install.sh"

version_package=$output_dir/.plasticine-cli-package
"$repo_dir/cli/build-version-package.sh" "$release_version" \
    "$output_dir/install.sh" "$repo_dir/cli/version-package/self-update" \
    "$version_package"
tar -czf "$output_dir/plasticine-cli.tar.gz" -C "$version_package" \
    plasticine install.sh self-update VERSION
rm -rf "$version_package"

(
    cd "$output_dir"
    shasum -a 256 install.sh plasticine-cli.tar.gz plasticine-source.bundle \
        plasticine-managed-plugins.tar.gz > SHA256SUMS
)

printf 'built release assets for %s in %s\n' "$revision" "$output_dir"
