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

# The Windows entry inlines the same lib/windows modules that a source checkout
# dot-sources. Keep this order in sync with $PlasticineLibraryModules in
# install.ps1; feature providers follow in sorted name order. Each module's bare
# dependency dot-sources are dropped because one file now holds every module.
powershell_library_dir=$repo_dir/lib/windows
powershell_library=$output_dir/.install.ps1.library
powershell_features=$output_dir/.install.ps1.features
[ -d "$powershell_library_dir" ] || {
    printf '%s\n' 'release PowerShell library is missing: lib/windows' >&2
    exit 1
}

append_powershell_module() {
    module_path=$1
    [ -f "$module_path" ] || {
        printf 'release PowerShell module is missing: %s\n' "$module_path" >&2
        exit 1
    }
    printf '# --- lib/windows/%s ---\n' "${module_path##*/}"
    awk '!/^\. \(Join-Path \$PSScriptRoot/' "$module_path"
}

: > "$powershell_library"
for module in common publish acl user-path chezmoi-bootstrap release-payload features config-apply; do
    append_powershell_module "$powershell_library_dir/$module.ps1" >> "$powershell_library"
done
find "$powershell_library_dir" -mindepth 1 -maxdepth 1 -type f -name 'feature-*.ps1' |
    LC_ALL=C sort > "$powershell_features"
while IFS= read -r module_path; do
    append_powershell_module "$module_path" >> "$powershell_library"
done < "$powershell_features"

awk -v revision="$revision" -v version="$release_version" \
    -v source_sha256="$source_sha256" -v plugins_sha256="$plugins_sha256" \
    -v library="$powershell_library" '
    /^\$PlasticineRepoRevision = \x27\x27$/ {
        print "$PlasticineRepoRevision = \x27" revision "\x27"
        revision_replaced++
        next
    }
    /^\$PlasticineReleaseVersion = \x27\x27$/ {
        print "$PlasticineReleaseVersion = \x27" version "\x27"
        version_replaced++
        next
    }
    /^\$PlasticineSourceSha256 = \x27\x27$/ {
        print "$PlasticineSourceSha256 = \x27" source_sha256 "\x27"
        source_replaced++
        next
    }
    /^\$PlasticinePluginsSha256 = \x27\x27$/ {
        print "$PlasticinePluginsSha256 = \x27" plugins_sha256 "\x27"
        plugins_replaced++
        next
    }
    /^# >>> plasticine-inline-library >>>$/ {
        print
        while ((getline module_line < library) > 0) print module_line
        close(library)
        while ((getline marker_line) > 0) {
            if (marker_line == "# <<< plasticine-inline-library <<<") {
                print marker_line
                library_replaced++
                next
            }
        }
        exit 1
    }
    { print }
    END {
        if (revision_replaced != 1 || version_replaced != 1 || source_replaced != 1 ||
            plugins_replaced != 1 || library_replaced != 1) exit 1
    }
' "$repo_dir/install.ps1" > "$output_dir/install.ps1" || {
    printf '%s\n' 'failed to inline release metadata and the PowerShell library into install.ps1' >&2
    exit 1
}
rm -f "$powershell_library" "$powershell_features"
if LC_ALL=C grep -Eq '^\. \(Join-Path \$PSScriptRoot' "$output_dir/install.ps1"; then
    printf '%s\n' 'release install.ps1 still dot-sources lib/windows' >&2
    exit 1
fi

# A real parser is the only trustworthy check of the generated entry: Windows
# PowerShell 5.1 is the documented baseline and pwsh covers the PowerShell 7
# host. Runners without either cannot validate the asset, so the Release
# workflow sets PLASTICINE_REQUIRE_POWERSHELL=1 to refuse an unparsed installer.
powershell_bin=${PLASTICINE_POWERSHELL_BIN:-}
if [ -z "$powershell_bin" ]; then
    powershell_bin=$(command -v pwsh 2>/dev/null || true)
fi
if [ -z "$powershell_bin" ]; then
    powershell_bin=$(command -v powershell 2>/dev/null || true)
fi
validate_powershell_syntax() {
    parsed_file=$1
    if [ -z "$powershell_bin" ]; then
        if [ "${PLASTICINE_REQUIRE_POWERSHELL:-0}" = 1 ]; then
            printf '%s\n' 'no PowerShell interpreter found to validate the release installer' >&2
            exit 1
        fi
        printf 'warning: no PowerShell interpreter found; not validating %s\n' "$parsed_file" >&2
        return 0
    fi
    parsed_path=$parsed_file
    if command -v cygpath >/dev/null 2>&1; then
        parsed_path=$(cygpath -w "$parsed_file")
    fi
    "$powershell_bin" -NoProfile -NonInteractive -Command '
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($args[0], [ref]$tokens, [ref]$errors)
        if ($null -ne $errors -and $errors.Count -gt 0) {
            foreach ($parseError in $errors) {
                [Console]::Error.WriteLine(($parseError.Extent.StartLineNumber.ToString() + ": " + $parseError.Message))
            }
            exit 1
        }' "$parsed_path" || {
        printf 'release installer does not parse on %s\n' "$powershell_bin" >&2
        exit 1
    }
}
validate_powershell_syntax "$output_dir/install.ps1"

version_package=$output_dir/.plasticine-cli-package
"$repo_dir/cli/build-version-package.sh" "$release_version" \
    "$output_dir/install.sh" "$repo_dir/cli/version-package/self-update" \
    "$version_package"
tar -czf "$output_dir/plasticine-cli.tar.gz" -C "$version_package" \
    plasticine install.sh self-update VERSION
rm -rf "$version_package"

(
    cd "$output_dir"
    shasum -a 256 install.sh install.ps1 plasticine-cli.tar.gz \
        plasticine-source.bundle plasticine-managed-plugins.tar.gz > SHA256SUMS
)

printf 'built release assets for %s in %s\n' "$revision" "$output_dir"
