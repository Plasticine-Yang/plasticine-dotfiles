#!/bin/sh

plasticine_lazygit_error() {
    printf 'plasticine-dotfiles: lazygit: %s\n' "$1" >&2
}

plasticine_lazygit_resolve() {
    command -v "$1" 2>/dev/null && return 0
    plasticine_lazygit_remaining=$PATH
    while :; do
        plasticine_lazygit_directory=${plasticine_lazygit_remaining%%:*}
        [ -n "$plasticine_lazygit_directory" ] || plasticine_lazygit_directory=.
        if [ -e "$plasticine_lazygit_directory/$1" ] || [ -L "$plasticine_lazygit_directory/$1" ]; then
            printf '%s\n' "$plasticine_lazygit_directory/$1"
            return 0
        fi
        case $plasticine_lazygit_remaining in
            *:*) plasticine_lazygit_remaining=${plasticine_lazygit_remaining#*:} ;;
            *) return 1 ;;
        esac
    done
}

plasticine_lazygit_real_directory() {
    [ -d "$1" ] && [ ! -L "$1" ]
}

plasticine_lazygit_validate_destination() {
    for plasticine_lazygit_parent in \
        "$lazygit_dest_dir" "$lazygit_dest_dir/.local" "$lazygit_install_dir"; do
        if [ -e "$plasticine_lazygit_parent" ] || [ -L "$plasticine_lazygit_parent" ]; then
            plasticine_lazygit_real_directory "$plasticine_lazygit_parent" || {
                plasticine_lazygit_error "installation parent is not a real directory: $plasticine_lazygit_parent"
                return 1
            }
        fi
    done
    if [ -e "$lazygit_target" ] || [ -L "$lazygit_target" ]; then
        [ -f "$lazygit_target" ] && [ ! -L "$lazygit_target" ] || {
            plasticine_lazygit_error "installation target is not a regular file: $lazygit_target; left untouched."
            return 1
        }
    fi
}

plasticine_lazygit_health() {
    [ -x "$1" ] && "$1" --version >/dev/null 2>&1
}

plasticine_lazygit_plan() {
    lazygit_dest_dir=$1
    case $lazygit_dest_dir in
        /*) ;;
        *) plasticine_lazygit_error 'destination must be an absolute path.'; return 1 ;;
    esac
    lazygit_install_dir=$lazygit_dest_dir/.local/bin
    lazygit_target=$lazygit_install_dir/lazygit
    lazygit_route=release
    lazygit_bin=''

    lazygit_host_os=${PLASTICINE_LAZYGIT_OS:-$(uname -s)} || return 1
    lazygit_host_arch=${PLASTICINE_LAZYGIT_ARCH:-$(uname -m)} || return 1
    case $lazygit_host_os in
        Darwin) lazygit_asset_os=darwin ;;
        Linux) lazygit_asset_os=linux ;;
        *) plasticine_lazygit_error "unsupported platform: $lazygit_host_os; no reviewed route or fallback."; return 1 ;;
    esac
    case $lazygit_host_arch in
        x86_64 | amd64) lazygit_asset_arch=x86_64 ;;
        arm64 | aarch64) lazygit_asset_arch=arm64 ;;
        *) plasticine_lazygit_error "unsupported architecture: $lazygit_host_arch; no reviewed route or fallback."; return 1 ;;
    esac

    plasticine_lazygit_validate_destination || return 1
    lazygit_bin=$(plasticine_lazygit_resolve lazygit) || lazygit_bin=''
    if [ -z "$lazygit_bin" ] && { [ -e "$lazygit_target" ] || [ -L "$lazygit_target" ]; }; then
        lazygit_bin=$lazygit_target
    fi
    if [ -n "$lazygit_bin" ]; then
        case $lazygit_bin in
            /*) ;;
            *) lazygit_bin=$(cd -- "$(dirname -- "$lazygit_bin")" 2>/dev/null && pwd -P)/${lazygit_bin##*/} ;;
        esac
        if ! plasticine_lazygit_health "$lazygit_bin"; then
            plasticine_lazygit_error "existing executable is unhealthy and was left untouched: $lazygit_bin; repair its installation owner, then retry. No fallback."
            return 1
        fi
        lazygit_route=existing
        return 0
    fi

    for plasticine_lazygit_command in curl tar awk mktemp mkdir chmod ln; do
        command -v "$plasticine_lazygit_command" >/dev/null 2>&1 || {
            plasticine_lazygit_error "missing command required by the official release route: $plasticine_lazygit_command"
            return 1
        }
    done
    if command -v sha256sum >/dev/null 2>&1; then
        lazygit_sha_command=sha256sum
    elif command -v shasum >/dev/null 2>&1; then
        lazygit_sha_command=shasum
    else
        plasticine_lazygit_error 'missing SHA-256 command (sha256sum or shasum); no fallback.'
        return 1
    fi
}

plasticine_lazygit_preview() {
    printf 'plasticine-dotfiles: lazygit: observed %s/%s; archive mapping %s/%s; route: %s\n' \
        "$lazygit_host_os" "$lazygit_host_arch" "$lazygit_asset_os" "$lazygit_asset_arch" "$lazygit_route"
    if [ "$lazygit_route" = existing ]; then
        printf '  Existing healthy executable: %s; version and installation owner remain untouched; network: none.\n' "$lazygit_bin"
        return 0
    fi
    printf '%s\n' \
        '  Official GitHub Release route; latest version is resolved only during apply; no installer script or fallback.' \
        '  network: HTTPS to api.github.com and github.com/jesseduffield/lazygit release assets.' \
        "  commands: curl release metadata; curl archive and same-release checksums.txt; $lazygit_sha_command SHA-256 verification; tar streams only the lazygit member." \
        "  destination: $lazygit_target (atomic publication, mode 0755, health checked before and after publication)." \
        '  package manager: none; privilege: none; credentials: none; terminal prompt: none.'
}

plasticine_lazygit_checksum() {
    awk -v wanted="$2" '
        {
            name = $NF
            sub(/^\*/, "", name)
            if (name == wanted) {
                seen++
                if (NF == 2 && $1 ~ /^[0-9A-Fa-f]{64}$/) { valid++; value=tolower($1) }
            }
        }
        END { if (seen == 1 && valid == 1) print value; else exit 1 }
    ' "$1"
}

plasticine_lazygit_actual_checksum() {
    case $lazygit_sha_command in
        sha256sum) sha256sum "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        shasum) shasum -a 256 "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        *) return 1 ;;
    esac
}

plasticine_lazygit_prepare() {
    [ "$lazygit_route" = release ] || {
        plasticine_lazygit_health "$lazygit_bin" || {
            plasticine_lazygit_error "existing executable became unhealthy and was left untouched: $lazygit_bin; repair it, then retry."
            return 1
        }
        return 0
    }

    lazygit_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-lazygit.XXXXXX") || {
        plasticine_lazygit_error 'could not create private temporary storage.'
        return 1
    }
    trap 'rm -rf "$lazygit_work_dir"' EXIT
    trap 'rm -rf "$lazygit_work_dir"; exit 1' HUP INT TERM
    lazygit_metadata=$lazygit_work_dir/latest.json
    lazygit_archive=$lazygit_work_dir/archive.tar.gz
    lazygit_checksums=$lazygit_work_dir/checksums.txt
    lazygit_extracted=$lazygit_work_dir/lazygit

    curl -fsSL -H 'Accept: application/vnd.github+json' \
        -o "$lazygit_metadata" https://api.github.com/repos/jesseduffield/lazygit/releases/latest || {
        plasticine_lazygit_error 'latest-release metadata download failed; no fallback or configuration applied.'
        return 1
    }
    lazygit_tag=$(awk '
        {
            rest=$0
            while (match(rest, /"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
                value=substr(rest, RSTART, RLENGTH); sub(/^.*"tag_name"[[:space:]]*:[[:space:]]*"/, "", value); sub(/"$/, "", value); count++; tag=value
                rest=substr(rest, RSTART + RLENGTH)
            }
        }
        END {if (count == 1) print tag; else exit 1}
    ' "$lazygit_metadata") || {
        plasticine_lazygit_error 'latest-release metadata did not contain exactly one tag_name; no fallback.'
        return 1
    }
    if ! printf '%s\n' "$lazygit_tag" | awk '/^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$/ {ok=1} END {exit !ok}'; then
        plasticine_lazygit_error "invalid latest-release tag: $lazygit_tag; no fallback."
        return 1
    fi
    lazygit_version=${lazygit_tag#v}
    lazygit_asset=lazygit_${lazygit_version}_${lazygit_asset_os}_${lazygit_asset_arch}.tar.gz
    lazygit_release_url=https://github.com/jesseduffield/lazygit/releases/download/$lazygit_tag
    curl -fsSL -o "$lazygit_archive" "$lazygit_release_url/$lazygit_asset" || {
        plasticine_lazygit_error "release archive download failed: $lazygit_asset; no fallback."
        return 1
    }
    curl -fsSL -o "$lazygit_checksums" "$lazygit_release_url/checksums.txt" || {
        plasticine_lazygit_error 'same-release checksums.txt download failed; no fallback.'
        return 1
    }
    lazygit_expected=$(plasticine_lazygit_checksum "$lazygit_checksums" "$lazygit_asset") || {
        plasticine_lazygit_error "checksums.txt must contain exactly one valid SHA-256 entry for $lazygit_asset; no fallback."
        return 1
    }
    lazygit_actual=$(plasticine_lazygit_actual_checksum "$lazygit_archive") || {
        plasticine_lazygit_error 'could not calculate the release archive SHA-256 checksum.'
        return 1
    }
    [ "$lazygit_expected" = "$lazygit_actual" ] || {
        plasticine_lazygit_error "SHA-256 mismatch for $lazygit_asset; archive rejected, no fallback."
        return 1
    }
    lazygit_member_count=$(tar -tzf "$lazygit_archive" 2>/dev/null | awk '$0 == "lazygit" {n++} END {print n+0}') || {
        plasticine_lazygit_error 'release archive listing failed; no fallback.'
        return 1
    }
    [ "$lazygit_member_count" -eq 1 ] || {
        plasticine_lazygit_error 'release archive must contain exactly one member named lazygit; no fallback.'
        return 1
    }
    tar -xOzf "$lazygit_archive" lazygit > "$lazygit_extracted" || {
        plasticine_lazygit_error 'release executable extraction failed; no fallback.'
        return 1
    }
    chmod 755 "$lazygit_extracted" || { plasticine_lazygit_error 'could not assign executable mode to extracted Lazygit.'; return 1; }
    plasticine_lazygit_health "$lazygit_extracted" || {
        plasticine_lazygit_error 'extracted Lazygit failed its --version health check; no publication or fallback.'
        return 1
    }

    plasticine_lazygit_validate_destination || return 1
    umask 077
    if [ ! -e "$lazygit_dest_dir/.local" ] && [ ! -L "$lazygit_dest_dir/.local" ]; then
        mkdir "$lazygit_dest_dir/.local" || { plasticine_lazygit_error 'could not create ~/.local'; return 1; }
    fi
    plasticine_lazygit_validate_destination || return 1
    if [ ! -e "$lazygit_install_dir" ] && [ ! -L "$lazygit_install_dir" ]; then
        mkdir "$lazygit_install_dir" || { plasticine_lazygit_error 'could not create ~/.local/bin'; return 1; }
    fi
    plasticine_lazygit_validate_destination || return 1
    [ ! -e "$lazygit_target" ] && [ ! -L "$lazygit_target" ] || {
        plasticine_lazygit_error "installation target appeared during installation and was left untouched: $lazygit_target"
        return 1
    }
    lazygit_stage=$(mktemp "$lazygit_install_dir/.lazygit.plasticine.XXXXXX") || {
        plasticine_lazygit_error 'could not create same-directory publication staging.'
        return 1
    }
    if ! (cat "$lazygit_extracted" > "$lazygit_stage" && chmod 755 "$lazygit_stage"); then
        rm -f "$lazygit_stage"
        plasticine_lazygit_error 'could not stage Lazygit for atomic publication.'
        return 1
    fi
    [ ! -e "$lazygit_target" ] && [ ! -L "$lazygit_target" ] || {
        rm -f "$lazygit_stage"
        plasticine_lazygit_error "installation target appeared during installation and was left untouched: $lazygit_target"
        return 1
    }
    # A hard link is an atomic no-clobber publication on the same filesystem.
    # Unlike mv, it cannot replace a target created after our final check.
    ln "$lazygit_stage" "$lazygit_target" || {
        rm -f "$lazygit_stage"
        plasticine_lazygit_error 'atomic no-clobber publication failed; the destination was left untouched.'
        return 1
    }
    rm -f "$lazygit_stage"
    if ! plasticine_lazygit_health "$lazygit_target"; then
        rm -f "$lazygit_target"
        plasticine_lazygit_error 'published Lazygit failed its --version health check and was removed; no configuration applied.'
        return 1
    fi
    lazygit_bin=$lazygit_target
    lazygit_route=existing
}
