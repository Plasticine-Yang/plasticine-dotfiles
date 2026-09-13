#!/bin/sh

plasticine_herdr_error() {
    printf 'plasticine-dotfiles: herdr: %s\n' "$1" >&2
}

plasticine_herdr_resolve() {
    command -v herdr 2>/dev/null && return 0
    plasticine_herdr_remaining=$PATH
    while :; do
        plasticine_herdr_directory=${plasticine_herdr_remaining%%:*}
        [ -n "$plasticine_herdr_directory" ] || plasticine_herdr_directory=.
        if [ -e "$plasticine_herdr_directory/herdr" ] || [ -L "$plasticine_herdr_directory/herdr" ]; then
            printf '%s\n' "$plasticine_herdr_directory/herdr"
            return 0
        fi
        case $plasticine_herdr_remaining in
            *:*) plasticine_herdr_remaining=${plasticine_herdr_remaining#*:} ;;
            *) return 1 ;;
        esac
    done
}

plasticine_herdr_absolute() {
    printf '%s/%s\n' "$(cd -- "$(dirname -- "$1")" 2>/dev/null && pwd -P)" "${1##*/}"
}

plasticine_herdr_validate_destination() {
    for plasticine_herdr_parent in "$herdr_dest_dir" "$herdr_dest_dir/.local" "$herdr_install_dir"; do
        if [ -e "$plasticine_herdr_parent" ] || [ -L "$plasticine_herdr_parent" ]; then
            [ -d "$plasticine_herdr_parent" ] && [ ! -L "$plasticine_herdr_parent" ] || {
                plasticine_herdr_error "installation parent is not a real directory: $plasticine_herdr_parent"
                return 1
            }
        fi
    done
    if [ -e "$herdr_target" ] || [ -L "$herdr_target" ]; then
        [ -f "$herdr_target" ] && [ ! -L "$herdr_target" ] || {
            plasticine_herdr_error "installation target is not a regular file: $herdr_target; left untouched."
            return 1
        }
    fi
}

plasticine_herdr_version() {
    [ -x "$1" ] || return 1
    plasticine_herdr_version_output=$("$1" --version 2>/dev/null) || return 1
    printf '%s\n' "$plasticine_herdr_version_output" | awk '
        { for (i=1; i<=NF; i++) if ($i ~ /^v?[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$/) {
            value=$i; sub(/^v/, "", value); count++
        }}
        END { if (count == 1) print value; else exit 1 }
    '
}

plasticine_herdr_stable_version() {
    printf '%s\n' "$1" | awk '/^[0-9]+\.[0-9]+\.[0-9]+$/ {print; ok=1} END {exit !ok}'
}

plasticine_herdr_compare() {
    awk -v left="$1" -v right="$2" 'BEGIN {
        split(left, a, "."); split(right, b, ".")
        for (i=1; i<=3; i++) {
            if ((a[i] + 0) < (b[i] + 0)) { print -1; exit }
            if ((a[i] + 0) > (b[i] + 0)) { print 1; exit }
        }
        print 0
    }'
}

plasticine_herdr_plan() {
    herdr_dest_dir=$1
    case $herdr_dest_dir in /*) ;; *) plasticine_herdr_error 'destination must be an absolute path.'; return 1 ;; esac
    if [ -d "$herdr_dest_dir" ] && [ ! -L "$herdr_dest_dir" ]; then
        herdr_dest_dir=$(cd -- "$herdr_dest_dir" && pwd -P) || return 1
    fi
    herdr_install_dir=$herdr_dest_dir/.local/bin
    herdr_target=$herdr_install_dir/herdr
    herdr_bin=''
    herdr_owner=missing
    herdr_observed=missing

    plasticine_herdr_validate_destination || return 1
    if [ -d "$herdr_install_dir" ] && [ ! -L "$herdr_install_dir" ]; then
        herdr_install_dir=$(cd -- "$herdr_install_dir" && pwd -P) || return 1
        herdr_target=$herdr_install_dir/herdr
    fi
    herdr_bin=$(plasticine_herdr_resolve) || herdr_bin=''
    if [ -z "$herdr_bin" ] && { [ -e "$herdr_target" ] || [ -L "$herdr_target" ]; }; then
        herdr_bin=$herdr_target
    fi
    if [ -n "$herdr_bin" ]; then
        herdr_bin=$(plasticine_herdr_absolute "$herdr_bin") || return 1
        if [ "$herdr_bin" = "$herdr_target" ]; then herdr_owner=direct; else herdr_owner=external; fi
        if herdr_observed=$(plasticine_herdr_version "$herdr_bin"); then :; else herdr_observed=unhealthy; fi
    fi
}

plasticine_herdr_preview() {
    printf 'plasticine-dotfiles: herdr: observed=%s; owner=%s; stable target resolved only during confirmed apply\n' "$herdr_observed" "$herdr_owner"
    printf '%s\n' \
        '  Missing: fully download https://herdr.dev/install.sh, then run it with HERDR_INSTALL_DIR in private candidate storage.' \
        '  Supported direct install: query https://herdr.dev/latest.json, then run herdr update without --handoff only when outdated.' \
        "  destination: $herdr_target; no package manager, sudo, aliases, shell edits, configuration, sessions, server launch, or agent integrations." \
        '  The official installer verifies manifest-provided SHA-256 within the same herdr.dev trust boundary; it is not an independent signature.' \
        '  Native update prompts remain native and explicit; refusal or required unattended interaction fails with retry guidance.'
    case :$PATH: in *:"$herdr_install_dir":*) ;; *) printf '  PATH: %s is not currently present; select shell too or add it yourself.\n' "$herdr_install_dir" ;; esac
}

plasticine_herdr_resolve_target() {
    herdr_manifest=$(mktemp "$herdr_work_dir/latest.XXXXXX") || return 1
    curl -fsSL -o "$herdr_manifest" https://herdr.dev/latest.json || {
        plasticine_herdr_error 'stable-release metadata lookup failed; the existing installation was left untouched.'
        return 1
    }
    herdr_latest=$(awk '
        {
            rest=$0
            while (match(rest, /"version"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
                value=substr(rest, RSTART, RLENGTH)
                sub(/^.*"version"[[:space:]]*:[[:space:]]*"/, "", value); sub(/"$/, "", value)
                count++; version=value; rest=substr(rest, RSTART + RLENGTH)
            }
        }
        END {if (count == 1) print version; else exit 1}
    ' "$herdr_manifest") || {
        plasticine_herdr_error 'stable-release manifest did not contain exactly one version.'
        return 1
    }
    herdr_latest=$(plasticine_herdr_stable_version "${herdr_latest#v}") || {
        plasticine_herdr_error "stable-release manifest contained an invalid or prerelease version: $herdr_latest"
        return 1
    }
}

plasticine_herdr_install_missing() {
    herdr_script=$herdr_work_dir/install.sh
    herdr_candidate_dir=$herdr_work_dir/candidate
    mkdir "$herdr_candidate_dir" || return 1
    curl -fsSL -o "$herdr_script" https://herdr.dev/install.sh || {
        plasticine_herdr_error 'official installer download failed; no command was published.'
        return 1
    }
    HERDR_INSTALL_DIR=$herdr_candidate_dir /bin/sh "$herdr_script" || {
        plasticine_herdr_error 'official installer failed (including any upstream download or checksum failure); no command was published.'
        return 1
    }
    herdr_candidate=$herdr_candidate_dir/herdr
    herdr_candidate_version=$(plasticine_herdr_version "$herdr_candidate") || {
        plasticine_herdr_error 'official installer candidate failed the noninteractive --version check; no command was published.'
        return 1
    }
    [ "$herdr_candidate_version" = "$herdr_latest" ] || {
        plasticine_herdr_error "official installer candidate is $herdr_candidate_version, not resolved stable target $herdr_latest; no command was published."
        return 1
    }
    plasticine_herdr_validate_destination || return 1
    umask 077
    [ -e "$herdr_dest_dir/.local" ] || mkdir "$herdr_dest_dir/.local" || return 1
    plasticine_herdr_validate_destination || return 1
    [ -e "$herdr_install_dir" ] || mkdir "$herdr_install_dir" || return 1
    plasticine_herdr_validate_destination || return 1
    [ ! -e "$herdr_target" ] && [ ! -L "$herdr_target" ] || {
        plasticine_herdr_error "installation target appeared during preparation and was left untouched: $herdr_target"; return 1;
    }
    herdr_stage=$(mktemp "$herdr_install_dir/.herdr.plasticine.XXXXXX") || return 1
    if ! (cat "$herdr_candidate" > "$herdr_stage" && chmod 755 "$herdr_stage"); then
        rm -f "$herdr_stage"; plasticine_herdr_error 'could not stage Herdr for publication.'; return 1
    fi
    [ ! -e "$herdr_target" ] && [ ! -L "$herdr_target" ] || {
        rm -f "$herdr_stage"; plasticine_herdr_error "installation target appeared during publication and was left untouched: $herdr_target"; return 1;
    }
    ln "$herdr_stage" "$herdr_target" || {
        rm -f "$herdr_stage"; plasticine_herdr_error 'atomic no-clobber publication failed; the destination was left untouched.'; return 1
    }
    rm -f "$herdr_stage"
    herdr_final=$(plasticine_herdr_version "$herdr_target") || {
        plasticine_herdr_error "published command failed --version and was retained at $herdr_target; inspect it before retrying."; return 1;
    }
    [ "$herdr_final" = "$herdr_latest" ] || { plasticine_herdr_error "published command did not remain at target $herdr_latest and was retained."; return 1; }
    printf 'plasticine-dotfiles: herdr: observed=missing; target=%s; action=install; result=current\n' "$herdr_latest"
}

plasticine_herdr_prepare() {
    for plasticine_herdr_command in curl awk mktemp mkdir chmod cat ln rm; do
        command -v "$plasticine_herdr_command" >/dev/null 2>&1 || { plasticine_herdr_error "missing required command: $plasticine_herdr_command"; return 1; }
    done
    herdr_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-herdr.XXXXXX") || { plasticine_herdr_error 'could not create private temporary storage.'; return 1; }
    trap 'rm -rf "$herdr_work_dir"' EXIT
    trap 'rm -rf "$herdr_work_dir"; exit 1' HUP INT TERM
    plasticine_herdr_resolve_target || return 1

    if [ "$herdr_owner" = missing ]; then plasticine_herdr_install_missing; return $?; fi
    [ "$herdr_observed" != unhealthy ] || { plasticine_herdr_error "existing executable is unhealthy and was left untouched: $herdr_bin; repair its owner, then retry."; return 1; }
    herdr_stable=$(plasticine_herdr_stable_version "$herdr_observed") || {
        plasticine_herdr_error "existing version is prerelease/custom ($herdr_observed); its channel was left unchanged. Select stable explicitly with Herdr, then retry."; return 1
    }
    if [ "$herdr_owner" = direct ]; then
        herdr_channel=$("$herdr_bin" channel show 2>/dev/null) || {
            plasticine_herdr_error 'could not establish the direct installation update channel; no update was attempted.'; return 1
        }
        [ "$herdr_channel" = stable ] || { plasticine_herdr_error "direct installation uses channel '$herdr_channel'; it was not changed or downgraded."; return 1; }
    fi
    if [ "$herdr_stable" = "$herdr_latest" ]; then
        printf 'plasticine-dotfiles: herdr: observed=%s; target=%s; owner=%s; action=reuse; result=current\n' "$herdr_stable" "$herdr_latest" "$herdr_owner"
        return 0
    fi
    if [ "$(plasticine_herdr_compare "$herdr_stable" "$herdr_latest")" -gt 0 ]; then
        plasticine_herdr_error "existing stable version $herdr_stable is newer than resolved target $herdr_latest; it was not downgraded. Retry after stable metadata catches up."
        return 1
    fi
    if [ "$herdr_owner" != direct ]; then
        plasticine_herdr_error "external installation at $herdr_bin is $herdr_stable, not stable target $herdr_latest; update it with its package manager/owner. No shadow copy was installed."
        return 1
    fi
    if ! "$herdr_bin" update; then
        plasticine_herdr_error 'native update did not complete. Plasticine did not answer prompts, stop sessions/servers, or request --handoff; retry in a terminal and authorize any intervention yourself.'
        return 1
    fi
    herdr_final=$(plasticine_herdr_version "$herdr_bin") || { plasticine_herdr_error 'native update completed but final --version verification failed.'; return 1; }
    [ "$herdr_final" = "$herdr_latest" ] || { plasticine_herdr_error "native update left version $herdr_final instead of stable target $herdr_latest; no success was claimed."; return 1; }
    printf 'plasticine-dotfiles: herdr: observed=%s; target=%s; owner=direct; action=update; result=current\n' "$herdr_stable" "$herdr_latest"
}
