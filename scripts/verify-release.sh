#!/bin/sh
set -eu

asset_dir=${1:-}
revision=${2:-}
release_version=${3:-}
chezmoi_bin=${CHEZMOI_BIN:-}

if [ -z "$asset_dir" ] || [ -z "$revision" ] || [ -z "$release_version" ]; then
    printf '%s\n' 'usage: scripts/verify-release.sh <asset-directory> <full-commit-id> <release-version>' >&2
    exit 2
fi
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
if ! printf '%s\n' "$release_version" |
    LC_ALL=C grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    printf '%s\n' 'release version must be a stable vMAJOR.MINOR.PATCH tag' >&2
    exit 2
fi
[ -n "$chezmoi_bin" ] || chezmoi_bin=$(command -v chezmoi)
[ -d "$asset_dir" ] || {
    printf '%s\n' 'release asset directory is missing' >&2
    exit 1
}
asset_dir=$(cd "$asset_dir" && pwd -P)

if [ ! -f "$asset_dir/install.sh" ] || [ ! -x "$asset_dir/install.sh" ]; then
    printf '%s\n' 'release install.sh is missing or not executable' >&2
    exit 1
fi
[ -f "$asset_dir/SHA256SUMS" ] || {
    printf '%s\n' 'release SHA256SUMS is missing' >&2
    exit 1
}
[ -f "$asset_dir/plasticine-source.bundle" ] &&
    [ -f "$asset_dir/plasticine-managed-plugins.tar.gz" ] &&
    [ -f "$asset_dir/plasticine-cli.tar.gz" ] &&
    [ -f "$asset_dir/install.ps1" ] || {
    printf '%s\n' 'release payload assets are missing' >&2
    exit 1
}
[ "$(find "$asset_dir" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 6 ] &&
    [ "$(find "$asset_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 6 ] || {
    printf '%s\n' 'release directory must contain exactly six expected assets' >&2
    exit 1
}

/bin/sh -n "$asset_dir/install.sh"
grep -Fqx "readonly_repo_revision='$revision'" "$asset_dir/install.sh" || {
    printf '%s\n' 'release installer does not pin the expected revision' >&2
    exit 1
}
grep -Fqx "readonly_release_version='$release_version'" "$asset_dir/install.sh" || {
    printf '%s\n' 'release installer does not contain the expected version' >&2
    exit 1
}
if grep -Fqx "readonly_repo_revision=''" "$asset_dir/install.sh"; then
    printf '%s\n' 'release installer still contains the development revision' >&2
    exit 1
fi
source_sha256=$(shasum -a 256 "$asset_dir/plasticine-source.bundle" | awk '{print $1}')
plugins_sha256=$(shasum -a 256 "$asset_dir/plasticine-managed-plugins.tar.gz" | awk '{print $1}')
if ! grep -Fqx "readonly_source_sha256='$source_sha256'" "$asset_dir/install.sh" ||
    ! grep -Fqx "readonly_plugins_sha256='$plugins_sha256'" "$asset_dir/install.sh"; then
    printf '%s\n' 'release installer does not pin the payload asset digests' >&2
    exit 1
fi

# The Windows entry pins the same release metadata and inlines the PowerShell
# library; it is a payload asset rather than an executable script.
installer_ps1=$asset_dir/install.ps1
grep -Fqx "\$PlasticineRepoRevision = '$revision'" "$installer_ps1" || {
    printf '%s\n' 'release install.ps1 does not pin the expected revision' >&2
    exit 1
}
grep -Fqx "\$PlasticineReleaseVersion = '$release_version'" "$installer_ps1" || {
    printf '%s\n' 'release install.ps1 does not contain the expected version' >&2
    exit 1
}
if grep -Fqx "\$PlasticineRepoRevision = ''" "$installer_ps1"; then
    printf '%s\n' 'release install.ps1 still contains the development revision' >&2
    exit 1
fi
if ! grep -Fqx "\$PlasticineSourceSha256 = '$source_sha256'" "$installer_ps1" ||
    ! grep -Fqx "\$PlasticinePluginsSha256 = '$plugins_sha256'" "$installer_ps1"; then
    printf '%s\n' 'release install.ps1 does not pin the payload asset digests' >&2
    exit 1
fi
# shellcheck disable=SC2016 # the single-quoted pattern is a literal PowerShell text match
if grep -Eq '^\. \(Join-Path \$PSScriptRoot' "$installer_ps1"; then
    printf '%s\n' 'release install.ps1 still dot-sources lib/windows' >&2
    exit 1
fi
powershell_bin=${PLASTICINE_POWERSHELL_BIN:-}
if [ -z "$powershell_bin" ]; then
    powershell_bin=$(command -v pwsh 2>/dev/null || true)
fi
if [ -z "$powershell_bin" ]; then
    powershell_bin=$(command -v powershell 2>/dev/null || true)
fi
if [ -n "$powershell_bin" ]; then
    parsed_installer=$installer_ps1
    if command -v cygpath >/dev/null 2>&1; then
        parsed_installer=$(cygpath -w "$installer_ps1")
    fi
    # Pass the validated path through the environment: Windows PowerShell 5.1
    # does not forward arguments after -Command to $args.
    # shellcheck disable=SC2016 # the payload is PowerShell source, not shell expansion
    PLASTICINE_PARSE_TARGET=$parsed_installer "$powershell_bin" -NoProfile -NonInteractive -Command '
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($env:PLASTICINE_PARSE_TARGET, [ref]$tokens, [ref]$errors)
        if ($null -ne $errors -and $errors.Count -gt 0) {
            foreach ($parseError in $errors) {
                [Console]::Error.WriteLine(($parseError.Extent.StartLineNumber.ToString() + ": " + $parseError.Message))
            }
            exit 1
        }' || {
        printf 'release install.ps1 does not parse on %s\n' "$powershell_bin" >&2
        exit 1
    }
else
    printf 'warning: no PowerShell interpreter found; not validating install.ps1\n' >&2
fi
(
    cd "$asset_dir"
    awk '
        NF != 2 || length($1) != 64 || $1 ~ /[^0-9A-Fa-f]/ { exit 1 }
        {
            if ($2 ~ /^[*]/) { $2 = substr($2, 2) }
        }
        $2 == "install.sh" || $2 == "install.ps1" || $2 == "plasticine-cli.tar.gz" ||
            $2 == "plasticine-managed-plugins.tar.gz" ||
            $2 == "plasticine-source.bundle" { seen[$2]++; next }
        { exit 1 }
        END {
            exit length(seen) != 5 || seen["install.sh"] != 1 ||
                seen["install.ps1"] != 1 ||
                seen["plasticine-cli.tar.gz"] != 1 ||
                seen["plasticine-managed-plugins.tar.gz"] != 1 ||
                seen["plasticine-source.bundle"] != 1
        }
    ' SHA256SUMS || {
        printf '%s\n' 'release SHA256SUMS must cover exactly the five payload assets' >&2
        exit 1
    }
)
(cd "$asset_dir" && shasum -a 256 -c SHA256SUMS)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-release-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
package_dir=$test_root/package
mkdir "$package_dir"
tar -tzf "$asset_dir/plasticine-cli.tar.gz" | awk '
    $0 == "plasticine" || $0 == "./plasticine" ||
        $0 == "install.sh" || $0 == "./install.sh" ||
        $0 == "self-update" || $0 == "./self-update" ||
        $0 == "VERSION" || $0 == "./VERSION" { seen[$0]++; next }
    { exit 1 }
    END {
        exit length(seen) != 4 || seen["plasticine"] + seen["./plasticine"] != 1 ||
            seen["install.sh"] + seen["./install.sh"] != 1 ||
            seen["self-update"] + seen["./self-update"] != 1 ||
            seen["VERSION"] + seen["./VERSION"] != 1
    }
' || {
    printf '%s\n' 'release CLI archive layout is invalid' >&2
    exit 1
}
tar -xzf "$asset_dir/plasticine-cli.tar.gz" -C "$package_dir"
[ "$(find "$package_dir" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4 ] &&
    [ "$(find "$package_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 4 ] &&
    [ -x "$package_dir/plasticine" ] &&
    [ -x "$package_dir/install.sh" ] &&
    [ -x "$package_dir/self-update" ] &&
    [ -f "$package_dir/VERSION" ] && [ ! -x "$package_dir/VERSION" ] || {
    printf '%s\n' 'release CLI archive files or modes are invalid' >&2
    exit 1
}
cmp -s "$asset_dir/install.sh" "$package_dir/install.sh" || {
    printf '%s\n' 'release installer differs from the packaged installer' >&2
    exit 1
}
[ "$(cat "$package_dir/VERSION")" = "$release_version" ] &&
    [ "$("$package_dir/plasticine" --version)" = "plasticine $release_version" ] || {
    printf '%s\n' 'release CLI package version or health check failed' >&2
    exit 1
}
/bin/sh -n "$package_dir/plasticine" "$package_dir/install.sh" "$package_dir/self-update"
git init -q --bare "$test_root/bundle-verify.git"
git -C "$test_root/bundle-verify.git" bundle verify \
    "$asset_dir/plasticine-source.bundle" >/dev/null 2>&1
git bundle list-heads "$asset_dir/plasticine-source.bundle" |
    awk -v revision="$revision" '
        $1 != revision { bad=1 }
        $2 != "HEAD" && $2 != "refs/heads/plasticine-release" { bad=1 }
        $2 == "HEAD" { head++ }
        $2 == "refs/heads/plasticine-release" { branch++ }
        END { exit bad || head != 1 || branch != 1 }
    ' || {
        printf '%s\n' 'source bundle contains unexpected refs or revisions' >&2
        exit 1
    }

mkdir -p "$test_root/home"
HOME=$test_root/home \
PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
PLASTICINE_RELEASE_ASSET_DIR=$asset_dir \
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
[ "$("$test_root/home/.local/bin/plasticine" --version)" = "plasticine $release_version" ] || {
    printf '%s\n' 'released bootstrap did not install a healthy plasticine command' >&2
    exit 1
}
ordinary_assets=$test_root/ordinary-assets
mkdir "$ordinary_assets"
cp "$asset_dir/plasticine-source.bundle" \
    "$asset_dir/plasticine-managed-plugins.tar.gz" "$ordinary_assets/"
HOME=$test_root/home \
PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
PLASTICINE_RELEASE_ASSET_DIR=$ordinary_assets \
PLASTICINE_CHEZMOI_SOURCE_DIR=$test_root/source \
PLASTICINE_CHEZMOI_CONFIG_FILE=$test_root/config/chezmoi.toml \
PLASTICINE_CHEZMOI_STATE_FILE=$test_root/config/chezmoistate.boltdb \
PLASTICINE_CHEZMOI_DEST_DIR=$test_root/home \
    "$test_root/home/.local/bin/plasticine" -y >/dev/null || {
    printf '%s\n' 'ordinary local invocation did not use its installed Release' >&2
    exit 1
}

printf 'release assets verified for %s\n' "$revision"
