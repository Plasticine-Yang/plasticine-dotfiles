#!/bin/sh

plasticine_chezmoi_error() {
    printf 'plasticine-dotfiles: chezmoi prerequisite: %s\n' "$1" >&2
}

plasticine_chezmoi_version() {
    [ -x "$1" ] || return 1
    "$1" --version 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                value=$i
                sub(/^v/, "", value)
                sub(/[,;]$/, "", value)
                if (value ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { seen++; version=value }
            }
        }
        END { if (seen == 1) print version; else exit 1 }
    '
}

plasticine_chezmoi_stable_version() {
    printf '%s\n' "$1" | awk '
        /^[0-9]+\.[0-9]+\.[0-9]+$/ { print; ok=1 }
        END { exit !ok }
    '
}

plasticine_chezmoi_compare() {
    awk -v left="$1" -v right="$2" 'BEGIN {
        split(left, a, "."); split(right, b, ".")
        for (i=1; i<=3; i++) {
            if (a[i]+0 < b[i]+0) { print -1; exit }
            if (a[i]+0 > b[i]+0) { print 1; exit }
        }
        print 0
    }'
}

plasticine_chezmoi_has_required_interface() {
    version=$(plasticine_chezmoi_version "$1") || return 1
    [ "$(plasticine_chezmoi_compare "$version" 2.72.1)" != -1 ]
}

plasticine_chezmoi_sha() {
    case $chezmoi_sha_command in
        sha256sum) sha256sum "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        shasum) shasum -a 256 "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        *) return 1 ;;
    esac
}

plasticine_chezmoi_checksum() {
    awk -v wanted="$2" '{
        name=$NF; sub(/^\*/, "", name)
        if (name == wanted) {
            seen++
            if (NF == 2 && $1 ~ /^[0-9A-Fa-f]{64}$/) { valid++; value=tolower($1) }
        }
    } END { if (seen == 1 && valid == 1) print value; else exit 1 }' "$1"
}

plasticine_chezmoi_validate_destination() {
    for parent in "$chezmoi_home" "$chezmoi_home/.local" "$chezmoi_install_dir"; do
        if [ -e "$parent" ] || [ -L "$parent" ]; then
            [ -d "$parent" ] && [ ! -L "$parent" ] || {
                plasticine_chezmoi_error "installation parent is not a real directory: $parent"
                return 1
            }
        fi
    done
    if [ -e "$chezmoi_target" ] || [ -L "$chezmoi_target" ]; then
        [ -f "$chezmoi_target" ] && [ ! -L "$chezmoi_target" ] || {
            plasticine_chezmoi_error "installation target is not a regular file: $chezmoi_target; left untouched."
            return 1
        }
    fi
}

plasticine_chezmoi_resolve_latest() {
    chezmoi_metadata=$chezmoi_work_dir/latest.json
    curl -fsSL -H 'Accept: application/vnd.github+json' -o "$chezmoi_metadata" \
        https://api.github.com/repos/twpayne/chezmoi/releases/latest || {
        plasticine_chezmoi_error 'latest stable release lookup failed; an older executable is not accepted as current.'
        return 1
    }
    chezmoi_tag=$(awk '{
        rest=$0
        while (match(rest, /"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
            value=substr(rest,RSTART,RLENGTH); sub(/^.*"tag_name"[[:space:]]*:[[:space:]]*"/,"",value); sub(/"$/,"",value); count++; tag=value
            rest=substr(rest,RSTART+RLENGTH)
        }
    } END { if (count == 1) print tag; else exit 1 }' "$chezmoi_metadata") || {
        plasticine_chezmoi_error 'latest release metadata did not contain exactly one tag_name.'
        return 1
    }
    case $chezmoi_tag in
        v*) chezmoi_latest=${chezmoi_tag#v} ;;
        *) plasticine_chezmoi_error "latest release tag is not a stable vMAJOR.MINOR.PATCH: $chezmoi_tag"; return 1 ;;
    esac
    plasticine_chezmoi_stable_version "$chezmoi_latest" >/dev/null || {
        plasticine_chezmoi_error "latest release tag is not a stable vMAJOR.MINOR.PATCH: $chezmoi_tag"
        return 1
    }
}

plasticine_chezmoi_bootstrap() {
    chezmoi_home=$1
    chezmoi_explicit=${2:-}
    case $chezmoi_home in /*) ;; *) plasticine_chezmoi_error 'HOME must be absolute.'; return 1 ;; esac
    chezmoi_install_dir=$chezmoi_home/.local/bin
    chezmoi_target=$chezmoi_install_dir/chezmoi
    plasticine_chezmoi_validate_destination || return 1

    chezmoi_bin=''
    chezmoi_owner=missing
    if [ -n "$chezmoi_explicit" ]; then
        case $chezmoi_explicit in
            */*) chezmoi_bin=$chezmoi_explicit ;;
            *) chezmoi_bin=$(command -v "$chezmoi_explicit" 2>/dev/null || true) ;;
        esac
        [ -n "$chezmoi_bin" ] || { plasticine_chezmoi_error "explicit executable was not found: $chezmoi_explicit"; return 1; }
        chezmoi_owner=explicit
    elif command -v chezmoi >/dev/null 2>&1; then
        chezmoi_bin=$(command -v chezmoi)
        chezmoi_owner=external
    elif [ -e "$chezmoi_target" ] || [ -L "$chezmoi_target" ]; then
        chezmoi_bin=$chezmoi_target
        chezmoi_owner=direct
    fi
    if [ -n "$chezmoi_bin" ]; then
        case $chezmoi_bin in /*) ;; *) chezmoi_bin=$(cd -- "$(dirname -- "$chezmoi_bin")" && pwd -P)/${chezmoi_bin##*/} ;; esac
        [ "$chezmoi_owner" != external ] || [ "$chezmoi_bin" != "$chezmoi_target" ] || chezmoi_owner=direct
        chezmoi_observed=$(plasticine_chezmoi_version "$chezmoi_bin") || {
            plasticine_chezmoi_error "existing executable is unhealthy or has an unverifiable/prerelease version: $chezmoi_bin; repair its owner, then retry."
            return 1
        }
    else
        chezmoi_observed=missing
    fi
    if [ "$chezmoi_owner" = explicit ]; then
        plasticine_chezmoi_has_required_interface "$chezmoi_bin" || {
            plasticine_chezmoi_error "explicit executable lacks the required chezmoi interface: $chezmoi_bin"
            return 1
        }
        log "Using explicit chezmoi executable override without ownership mutation: $chezmoi_bin ($chezmoi_observed)."
        return 0
    fi

    for command_name in curl awk mktemp mkdir chmod tar cp ln mv; do
        command -v "$command_name" >/dev/null 2>&1 || { plasticine_chezmoi_error "missing release-route command: $command_name"; return 1; }
    done
    if command -v sha256sum >/dev/null 2>&1; then chezmoi_sha_command=sha256sum
    elif command -v shasum >/dev/null 2>&1; then chezmoi_sha_command=shasum
    else plasticine_chezmoi_error 'missing SHA-256 command (sha256sum or shasum).'; return 1
    fi
    chezmoi_os=${PLASTICINE_CHEZMOI_OS:-$(uname -s)}
    chezmoi_arch=${PLASTICINE_CHEZMOI_ARCH:-$(uname -m)}
    case $chezmoi_os in Darwin) chezmoi_asset_os=darwin ;; Linux) chezmoi_asset_os=linux ;; *) plasticine_chezmoi_error "unsupported platform: $chezmoi_os"; return 1 ;; esac
    case $chezmoi_arch in x86_64|amd64) chezmoi_asset_arch=amd64 ;; arm64|aarch64) chezmoi_asset_arch=arm64 ;; *) plasticine_chezmoi_error "unsupported architecture: $chezmoi_arch"; return 1 ;; esac
    chezmoi_observed_hash=''
    if [ "$chezmoi_owner" = direct ]; then
        chezmoi_observed_hash=$(plasticine_chezmoi_sha "$chezmoi_target") || return 1
    fi

    log 'Maintaining chezmoi prerequisite before source acquisition and Feature confirmation; cancellation will not undo this work.'
    chezmoi_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-chezmoi.XXXXXX") || return 1
    trap 'rm -rf "$chezmoi_work_dir"' EXIT
    trap 'rm -rf "$chezmoi_work_dir"; exit 1' HUP INT TERM
    plasticine_chezmoi_resolve_latest || return 1
    if [ "$chezmoi_observed" = missing ]; then chezmoi_action=install
    else
        chezmoi_comparison=$(plasticine_chezmoi_compare "$chezmoi_observed" "$chezmoi_latest")
        case $chezmoi_comparison in
            0) chezmoi_action=reuse ;;
            -1) chezmoi_action=update ;;
            *) plasticine_chezmoi_error "installed stable version $chezmoi_observed is newer than latest stable $chezmoi_latest; refusing a downgrade or channel takeover."; return 1 ;;
        esac
    fi
    log "chezmoi prerequisite: source=official GitHub latest stable; observed=$chezmoi_observed; target=$chezmoi_latest; action=$chezmoi_action."
    if [ "$chezmoi_action" = reuse ]; then
        log "chezmoi prerequisite: current executable reused without replacement: $chezmoi_bin"
        return 0
    fi
    if [ "$chezmoi_action" = update ] && [ "$chezmoi_owner" != direct ]; then
        plasticine_chezmoi_error "$chezmoi_bin is outdated ($chezmoi_observed) but owned by the $chezmoi_owner route; update it through that owner to $chezmoi_latest. It was left untouched and no shadow copy was installed."
        return 1
    fi

    chezmoi_asset=chezmoi_${chezmoi_latest}_${chezmoi_asset_os}_${chezmoi_asset_arch}.tar.gz
    chezmoi_checksums=chezmoi_${chezmoi_latest}_checksums.txt
    chezmoi_release_url=https://github.com/twpayne/chezmoi/releases/download/$chezmoi_tag
    chezmoi_archive=$chezmoi_work_dir/$chezmoi_asset
    chezmoi_checksum_file=$chezmoi_work_dir/$chezmoi_checksums
    curl -fsSL -o "$chezmoi_archive" "$chezmoi_release_url/$chezmoi_asset" || { plasticine_chezmoi_error 'release archive download failed; existing executable preserved.'; return 1; }
    curl -fsSL -o "$chezmoi_checksum_file" "$chezmoi_release_url/$chezmoi_checksums" || { plasticine_chezmoi_error 'release checksum download failed; existing executable preserved.'; return 1; }
    chezmoi_expected=$(plasticine_chezmoi_checksum "$chezmoi_checksum_file" "$chezmoi_asset") || { plasticine_chezmoi_error 'release checksum entry is missing or ambiguous; existing executable preserved.'; return 1; }
    chezmoi_actual=$(plasticine_chezmoi_sha "$chezmoi_archive") || return 1
    [ "$chezmoi_expected" = "$chezmoi_actual" ] || { plasticine_chezmoi_error 'release archive SHA-256 mismatch; existing executable preserved.'; return 1; }
    [ "$(tar -tzf "$chezmoi_archive" 2>/dev/null | awk '$0 == "chezmoi" {n++} END {print n+0}')" -eq 1 ] || { plasticine_chezmoi_error 'release archive must contain exactly one top-level chezmoi executable.'; return 1; }
    chezmoi_candidate=$chezmoi_work_dir/chezmoi
    tar -xOzf "$chezmoi_archive" chezmoi > "$chezmoi_candidate" || return 1
    chmod 755 "$chezmoi_candidate" || return 1
    [ "$(plasticine_chezmoi_version "$chezmoi_candidate" || true)" = "$chezmoi_latest" ] || { plasticine_chezmoi_error 'release candidate failed version/health validation; existing executable preserved.'; return 1; }

    plasticine_chezmoi_validate_destination || return 1
    umask 077
    [ -e "$chezmoi_home/.local" ] || mkdir "$chezmoi_home/.local" || return 1
    [ -e "$chezmoi_install_dir" ] || mkdir "$chezmoi_install_dir" || return 1
    plasticine_chezmoi_validate_destination || return 1
    chezmoi_stage=$(mktemp "$chezmoi_install_dir/.chezmoi.plasticine.XXXXXX") || return 1
    if ! (cp "$chezmoi_candidate" "$chezmoi_stage" && chmod 755 "$chezmoi_stage"); then rm -f "$chezmoi_stage"; return 1; fi
    if [ "$chezmoi_action" = install ]; then
        [ ! -e "$chezmoi_target" ] && [ ! -L "$chezmoi_target" ] || { rm -f "$chezmoi_stage"; plasticine_chezmoi_error 'installation target appeared during preparation; left untouched.'; return 1; }
        ln "$chezmoi_stage" "$chezmoi_target" || { rm -f "$chezmoi_stage"; plasticine_chezmoi_error 'atomic no-clobber publication failed.'; return 1; }
        rm -f "$chezmoi_stage"
    else
        [ "$(plasticine_chezmoi_sha "$chezmoi_target" 2>/dev/null || true)" = "$chezmoi_observed_hash" ] || { rm -f "$chezmoi_stage"; plasticine_chezmoi_error 'installation target changed during preparation; update aborted.'; return 1; }
        mv -f "$chezmoi_stage" "$chezmoi_target" || { rm -f "$chezmoi_stage"; plasticine_chezmoi_error 'atomic replacement failed; inspect the retained destination.'; return 1; }
    fi
    [ "$(plasticine_chezmoi_version "$chezmoi_target" || true)" = "$chezmoi_latest" ] || { plasticine_chezmoi_error "published executable failed health validation and was retained at $chezmoi_target; repair it before retrying."; return 1; }
    chezmoi_bin=$chezmoi_target
    log "chezmoi prerequisite: $chezmoi_action completed at $chezmoi_bin ($chezmoi_latest)."
}
