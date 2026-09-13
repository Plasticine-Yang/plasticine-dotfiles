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

plasticine_lazygit_version() {
    [ -x "$1" ] || return 1
    "$1" --version 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                value=$i
                sub(/^version=/, "", value)
                sub(/,$/, "", value)
                if (value ~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/) {
                    sub(/^v/, "", value); seen++; version=value
                }
            }
        }
        END { if (seen == 1) print version; else exit 1 }
    '
}

plasticine_lazygit_compare_versions() {
    awk -v left="$1" -v right="$2" 'BEGIN {
        split(left, l, "."); split(right, r, ".")
        for (i=1; i<=3; i++) {
            if ((l[i]+0) < (r[i]+0)) { print -1; exit }
            if ((l[i]+0) > (r[i]+0)) { print 1; exit }
        }
        print 0
    }'
}

plasticine_lazygit_plan() {
    lazygit_dest_dir=$1
    case $lazygit_dest_dir in
        /*) ;;
        *) plasticine_lazygit_error 'destination must be an absolute path.'; return 1 ;;
    esac
    lazygit_install_dir=$lazygit_dest_dir/.local/bin
    lazygit_target=$lazygit_install_dir/lazygit
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
    if [ -z "$lazygit_bin" ] && [ -f "$lazygit_target" ] && [ ! -L "$lazygit_target" ]; then
        lazygit_bin=$lazygit_target
    fi
    if [ -n "$lazygit_bin" ]; then
        case $lazygit_bin in
            /*) ;;
            *) lazygit_bin=$(cd -- "$(dirname -- "$lazygit_bin")" 2>/dev/null && pwd -P)/${lazygit_bin##*/} ;;
        esac
    fi

    for plasticine_lazygit_command in curl tar awk mktemp mkdir chmod ln mv; do
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
    printf 'plasticine-dotfiles: lazygit: observed %s/%s; archive mapping %s/%s\n' \
        "$lazygit_host_os" "$lazygit_host_arch" "$lazygit_asset_os" "$lazygit_asset_arch"
    printf '%s\n' \
        '  Fixed supported baseline: Lazygit 0.65.1 from its exact official versioned GitHub Release asset.' \
        '  A missing tool is installed; an authorized outdated direct installation is safely replaced; a current tool is retained.' \
        '  Existing prerelease, custom, unhealthy, ambiguous, and unsupported-owner installations are not replaced.' \
        '  network during apply: HTTPS to the pinned github.com/jesseduffield/lazygit release asset only when replacement is needed.' \
        "  commands during apply: curl archive; $lazygit_sha_command verification against its reviewed pinned SHA-256; tar streams only the lazygit member." \
        "  destination: $lazygit_target (fresh atomic no-clobber publication; authorized upgrades use checked same-directory atomic replacement)." \
        '  package manager: none; privilege: none; credentials: none; terminal prompt: none.'
    if [ -n "$lazygit_bin" ]; then
        printf '  Observed executable: %s; its version and owner will be classified during apply.\n' "$lazygit_bin"
    fi
}

plasticine_lazygit_actual_checksum() {
    case $lazygit_sha_command in
        sha256sum) sha256sum "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        shasum) shasum -a 256 "$1" | awk 'NF == 2 {print tolower($1)}' ;;
        *) return 1 ;;
    esac
}

plasticine_lazygit_prepare() {
    lazygit_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-lazygit.XXXXXX") || {
        plasticine_lazygit_error 'could not create private temporary storage.'
        return 1
    }
    trap 'rm -rf "$lazygit_work_dir"' EXIT
    trap 'rm -rf "$lazygit_work_dir"; exit 1' HUP INT TERM
    lazygit_archive=$lazygit_work_dir/archive.tar.gz
    lazygit_extracted=$lazygit_work_dir/lazygit
    lazygit_version=0.65.1
    lazygit_tag=v$lazygit_version
    lazygit_asset=lazygit_${lazygit_version}_${lazygit_asset_os}_${lazygit_asset_arch}.tar.gz
    case $lazygit_asset in
        lazygit_0.65.1_darwin_arm64.tar.gz) lazygit_expected=65a367c6ea9a88efebaaf7998a6835eedb987e04916cef677264ff9b31b1b13e ;;
        lazygit_0.65.1_darwin_x86_64.tar.gz) lazygit_expected=fde13daf583511aa24c42ca154911643231a5af784c7cdd8117264b2fc035b33 ;;
        lazygit_0.65.1_linux_arm64.tar.gz) lazygit_expected=49abecdf6adf4f2dfdb11bf7b9bfada267ea523612ed809d1c6d87f6c04000a7 ;;
        lazygit_0.65.1_linux_x86_64.tar.gz) lazygit_expected=02beacbcda0fa342e50ae3480ba8147307353af3fb28e1d5f790e02329c201a6 ;;
        *) plasticine_lazygit_error "no reviewed artifact tuple for $lazygit_asset"; return 1 ;;
    esac

    # Re-observe at confirmed apply. Only the managed direct pathname is
    # an authorized replacement owner; a current executable elsewhere may be
    # retained, but it cannot be updated by publishing a shadowing second copy.
    lazygit_bin=$(plasticine_lazygit_resolve lazygit) || lazygit_bin=''
    if [ -z "$lazygit_bin" ] && [ -f "$lazygit_target" ] && [ ! -L "$lazygit_target" ]; then
        lazygit_bin=$lazygit_target
    fi
    if [ -n "$lazygit_bin" ]; then
        case $lazygit_bin in
            /*) ;;
            *) lazygit_bin=$(cd -- "$(dirname -- "$lazygit_bin")" 2>/dev/null && pwd -P)/${lazygit_bin##*/} ;;
        esac
        plasticine_lazygit_health "$lazygit_bin" || {
            plasticine_lazygit_error "existing executable is unhealthy and was left untouched: $lazygit_bin; repair its installation owner, then retry. No fallback."
            return 1
        }
        lazygit_installed_version=$(plasticine_lazygit_version "$lazygit_bin") || {
            plasticine_lazygit_error "existing executable has a custom, prerelease, or unparseable version and was left untouched: $lazygit_bin; use its owner to select the stable channel."
            return 1
        }
        lazygit_comparison=$(plasticine_lazygit_compare_versions "$lazygit_installed_version" "$lazygit_version")
        case $lazygit_comparison in
            0|1)
                printf 'plasticine-dotfiles: lazygit: pinned baseline %s is satisfied by stable %s at %s; no release request or replacement.\n' "$lazygit_version" "$lazygit_installed_version" "$lazygit_bin"
                return 0
                ;;
            -1)
                [ "$lazygit_bin" = "$lazygit_target" ] || {
                    plasticine_lazygit_error "outdated Lazygit $lazygit_installed_version at unsupported owner path $lazygit_bin; update it with its owner or remove it from PATH before retrying. No shadow installation was created."
                    return 1
                }
                lazygit_publication=upgrade
                lazygit_original_checksum=$(plasticine_lazygit_actual_checksum "$lazygit_target") || return 1
                ;;
        esac
    else
        lazygit_publication=fresh
    fi

    lazygit_release_url=https://github.com/jesseduffield/lazygit/releases/download/$lazygit_tag
    curl -fsSL -o "$lazygit_archive" "$lazygit_release_url/$lazygit_asset" || {
        plasticine_lazygit_error "release archive download failed: $lazygit_asset; active installation was left untouched."
        return 1
    }
    lazygit_actual=$(plasticine_lazygit_actual_checksum "$lazygit_archive") || {
        plasticine_lazygit_error 'could not calculate the release archive SHA-256 checksum; active installation was left untouched.'
        return 1
    }
    [ "$lazygit_expected" = "$lazygit_actual" ] || {
        plasticine_lazygit_error "SHA-256 mismatch for $lazygit_asset; active installation was left untouched."
        return 1
    }
    lazygit_member_count=$(tar -tzf "$lazygit_archive" 2>/dev/null | awk '$0 == "lazygit" {n++} END {print n+0}') || {
        plasticine_lazygit_error 'release archive listing failed; active installation was left untouched.'
        return 1
    }
    [ "$lazygit_member_count" -eq 1 ] || {
        plasticine_lazygit_error 'release archive must contain exactly one member named lazygit; active installation was left untouched.'
        return 1
    }
    tar -xOzf "$lazygit_archive" lazygit > "$lazygit_extracted" || {
        plasticine_lazygit_error 'release executable extraction failed; active installation was left untouched.'
        return 1
    }
    chmod 755 "$lazygit_extracted" || { plasticine_lazygit_error 'could not assign executable mode to extracted Lazygit.'; return 1; }
    lazygit_candidate_version=$(plasticine_lazygit_version "$lazygit_extracted") || {
        plasticine_lazygit_error 'extracted Lazygit has an unparseable version; active installation was left untouched.'
        return 1
    }
    [ "$lazygit_candidate_version" = "$lazygit_version" ] || {
        plasticine_lazygit_error "extracted Lazygit version $lazygit_candidate_version does not match resolved target $lazygit_version; active installation was left untouched."
        return 1
    }

    plasticine_lazygit_validate_destination || return 1
    umask 077
    if [ ! -e "$lazygit_dest_dir/.local" ]; then
        mkdir "$lazygit_dest_dir/.local" || { plasticine_lazygit_error 'could not create ~/.local'; return 1; }
    fi
    plasticine_lazygit_validate_destination || return 1
    if [ ! -e "$lazygit_install_dir" ]; then
        mkdir "$lazygit_install_dir" || { plasticine_lazygit_error 'could not create ~/.local/bin'; return 1; }
    fi
    plasticine_lazygit_validate_destination || return 1
    lazygit_stage=$(mktemp "$lazygit_install_dir/.lazygit.plasticine.XXXXXX") || {
        plasticine_lazygit_error 'could not create same-directory publication staging.'
        return 1
    }
    if ! (cat "$lazygit_extracted" > "$lazygit_stage" && chmod 755 "$lazygit_stage"); then
        rm -f "$lazygit_stage"
        plasticine_lazygit_error 'could not stage Lazygit for atomic publication.'
        return 1
    fi

    case $lazygit_publication in
        fresh)
            [ ! -e "$lazygit_target" ] && [ ! -L "$lazygit_target" ] || {
                rm -f "$lazygit_stage"; plasticine_lazygit_error "installation target appeared during installation and was left untouched: $lazygit_target"; return 1
            }
            ln "$lazygit_stage" "$lazygit_target" || {
                rm -f "$lazygit_stage"; plasticine_lazygit_error 'atomic no-clobber publication failed; the destination was left untouched.'; return 1
            }
            rm -f "$lazygit_stage"
            ;;
        upgrade)
            plasticine_lazygit_validate_destination || { rm -f "$lazygit_stage"; return 1; }
            lazygit_revalidated_checksum=$(plasticine_lazygit_actual_checksum "$lazygit_target") || { rm -f "$lazygit_stage"; return 1; }
            [ "$lazygit_revalidated_checksum" = "$lazygit_original_checksum" ] || {
                rm -f "$lazygit_stage"; plasticine_lazygit_error 'authorized upgrade target changed during candidate preparation; replacement aborted.'; return 1
            }
            mv -f "$lazygit_stage" "$lazygit_target" || {
                rm -f "$lazygit_stage"; plasticine_lazygit_error 'atomic authorized upgrade replacement failed; inspect the active destination before retrying.'; return 1
            }
            ;;
    esac

    lazygit_result_version=$(plasticine_lazygit_version "$lazygit_target") || {
        plasticine_lazygit_error "the executable retained at $lazygit_target failed post-publication version verification; repair the Owner file, or remove it if it is the failed publication, before rerunning. Configuration was not applied."
        return 1
    }
    [ "$lazygit_result_version" = "$lazygit_version" ] || {
        plasticine_lazygit_error "post-publication version $lazygit_result_version does not match resolved target $lazygit_version; configuration was not applied."
        return 1
    }
    printf 'plasticine-dotfiles: lazygit: %s completed at stable target %s: %s\n' "$lazygit_publication" "$lazygit_version" "$lazygit_target"
}
