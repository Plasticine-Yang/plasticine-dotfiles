#!/bin/sh
# Planning reads the caller's environment; the native installer and self update
# override HOME and PATH only inside subshells.
# shellcheck disable=SC2030,SC2031

plasticine_uv_error() {
    printf 'plasticine-dotfiles: uv: %s\n' "$1" >&2
}

plasticine_uv_log() {
    printf 'plasticine-dotfiles: %s\n' "$1"
}

# Inspect PATH entries, including broken or non-executable installations.
plasticine_uv_resolve() {
    plasticine_uv_path=$PATH
    while :; do
        plasticine_uv_dir=${plasticine_uv_path%%:*}
        [ -n "$plasticine_uv_dir" ] || plasticine_uv_dir=.
        if [ -e "$plasticine_uv_dir/$1" ] || [ -L "$plasticine_uv_dir/$1" ]; then
            printf '%s/%s\n' "$(cd -- "$plasticine_uv_dir" && pwd -P)" "$1"
            return 0
        fi
        case $plasticine_uv_path in
            *:*) plasticine_uv_path=${plasticine_uv_path#*:} ;;
            *) return 1 ;;
        esac
    done
}

# Accept only one stable MAJOR.MINOR.PATCH token on the first output line.
plasticine_uv_version() {
    [ -f "$1" ] && [ -x "$1" ] || return 1
    plasticine_uv_version_output=$("$1" --version 2>/dev/null) || return 1
    printf '%s\n' "$plasticine_uv_version_output" | LC_ALL=C awk '
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                value = $i
                sub(/^v/, "", value)
                if (value ~ /^[0-9]+\.[0-9]+\.[0-9]+$/) { seen++; version = value }
            }
        }
        END { if (seen == 1) print version; else exit 1 }
    '
}

plasticine_uv_receipt_prefix() {
    [ -f "$uv_receipt" ] || return 1
    LC_ALL=C sed -n 's/.*"install_prefix"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$uv_receipt" | head -n 1
}

plasticine_uv_validate_destination() {
    if [ ! -d "$uv_dest" ] || [ -L "$uv_dest" ]; then
        plasticine_uv_error "destination must be an existing real directory: $uv_dest"
        return 1
    fi
    for plasticine_uv_parent in "$uv_dest/.local" "$uv_bin_dir" "$uv_config_base" "$uv_config_dir"; do
        if [ -e "$plasticine_uv_parent" ] || [ -L "$plasticine_uv_parent" ]; then
            [ -d "$plasticine_uv_parent" ] && [ ! -L "$plasticine_uv_parent" ] || {
                plasticine_uv_error "managed directory must be a real directory: $plasticine_uv_parent; left untouched."
                return 1
            }
        fi
    done
    for plasticine_uv_file in "$uv_target" "$uvx_target" "$uv_receipt"; do
        if [ -e "$plasticine_uv_file" ] || [ -L "$plasticine_uv_file" ]; then
            [ -f "$plasticine_uv_file" ] && [ ! -L "$plasticine_uv_file" ] || {
                plasticine_uv_error "managed path must be a regular file: $plasticine_uv_file; left untouched."
                return 1
            }
        fi
    done
}

plasticine_uv_plan() {
    uv_dest=$1
    case $uv_dest in
        /*) ;;
        *) plasticine_uv_error 'destination must be absolute.'; return 1 ;;
    esac
    uv_xdg_config=${XDG_CONFIG_HOME:-}
    if [ -n "$uv_xdg_config" ]; then
        case $uv_xdg_config in
            /*) ;;
            *) plasticine_uv_error 'XDG_CONFIG_HOME must be absolute.'; return 1 ;;
        esac
        uv_config_base=$uv_xdg_config
    else
        uv_config_base=$uv_dest/.config
    fi
    uv_bin_dir=$uv_dest/.local/bin
    uv_target=$uv_bin_dir/uv
    uvx_target=$uv_bin_dir/uvx
    uv_config_dir=$uv_config_base/uv
    uv_receipt=$uv_config_dir/uv-receipt.json
    plasticine_uv_validate_destination || return 1
    uv_dest=$(cd -- "$uv_dest" && pwd -P) || return 1
    [ -n "$uv_xdg_config" ] || uv_config_base=$uv_dest/.config
    uv_bin_dir=$uv_dest/.local/bin
    uv_target=$uv_bin_dir/uv
    uvx_target=$uv_bin_dir/uvx
    uv_config_dir=$uv_config_base/uv
    uv_receipt=$uv_config_dir/uv-receipt.json

    uv_os=${PLASTICINE_UV_OS:-$(uname -s)}
    uv_arch=${PLASTICINE_UV_ARCH:-$(uname -m)}
    case $uv_os:$uv_arch in
        Darwin:arm64|Darwin:aarch64|Darwin:x86_64|Linux:arm64|Linux:aarch64|Linux:x86_64|Linux:amd64) ;;
        *)
            plasticine_uv_error "no reviewed route for $uv_os/$uv_arch."
            return 1 ;;
    esac

    uv_path_bin=$(plasticine_uv_resolve uv) || uv_path_bin=''
    uv_path_uvx=$(plasticine_uv_resolve uvx) || uv_path_uvx=''
    if [ -n "$uv_path_bin" ] && [ "$uv_path_bin" != "$uv_target" ]; then
        plasticine_uv_error "external uv at $uv_path_bin; maintain it through its owner. No shadow installation."
        return 1
    fi
    if [ -n "$uv_path_uvx" ] && [ "$uv_path_uvx" != "$uvx_target" ]; then
        plasticine_uv_error "external uvx at $uv_path_uvx; maintain it through its owner. No shadow installation."
        return 1
    fi

    uv_owner=missing
    uv_observed=missing
    uvx_observed=missing
    uv_receipt_state=missing
    uv_receipt_prefix=''
    uv_route=install
    uv_route_reason='no managed installation'
    if [ -f "$uv_receipt" ] && [ ! -L "$uv_receipt" ]; then
        uv_receipt_state=present
        uv_receipt_prefix=$(plasticine_uv_receipt_prefix) || uv_receipt_prefix=''
    fi

    if [ -e "$uv_target" ] || [ -L "$uv_target" ]; then
        uv_owner=managed
        uv_observed=$(plasticine_uv_version "$uv_target") || {
            plasticine_uv_error "managed uv is unhealthy or has an unverifiable/prerelease/custom version: $uv_target; repair it before retrying."
            return 1
        }
        if [ -e "$uvx_target" ] || [ -L "$uvx_target" ]; then
            uvx_observed=$(plasticine_uv_version "$uvx_target") || {
                plasticine_uv_error "managed uvx is unhealthy or has an unverifiable/prerelease/custom version: $uvx_target; repair it before retrying."
                return 1
            }
        fi
        if [ "$uvx_observed" = missing ]; then
            uv_route=repair
            uv_route_reason='uvx is missing'
        elif [ "$uvx_observed" != "$uv_observed" ]; then
            uv_route=repair
            uv_route_reason='uv and uvx versions differ'
        elif [ "$uv_receipt_state" = missing ]; then
            uv_route=repair
            uv_route_reason='updater receipt is missing'
        elif [ "$uv_receipt_prefix" != "$uv_bin_dir" ]; then
            uv_route=repair
            uv_route_reason='updater receipt points to another prefix'
        else
            uv_route=self-update
            uv_route_reason='managed installation with matching updater receipt'
        fi
    elif [ -e "$uvx_target" ] || [ -L "$uvx_target" ]; then
        uv_owner=partial
        uv_route=repair
        uv_route_reason='uvx exists without uv'
    fi
}

plasticine_uv_preview() {
    printf 'plasticine-dotfiles: uv: platform=%s/%s; observed=%s; uvx=%s; owner=%s; route=%s\n' \
        "$uv_os" "$uv_arch" "$uv_observed" "$uvx_observed" "$uv_owner" "$uv_route"
    printf '  reason: %s\n' "$uv_route_reason"
    if [ "$uv_route" = self-update ]; then
        printf '%s\n' \
            '  After confirmation: run uv self update with UV_NO_MODIFY_PATH=1, then re-verify uv and uvx.' \
            '  The updater re-runs the official installer and writes only its native installation state.'
    else
        printf '%s\n' \
            '  After confirmation: download https://astral.sh/uv/install.sh completely, then run it with UV_INSTALL_DIR and UV_NO_MODIFY_PATH=1.' \
            "  uv and uvx are installed into $uv_bin_dir; the installer writes the updater receipt used by later self updates."
        if [ "$uv_os" = Darwin ]; then
            printf '%s\n' '  macOS has no sha256sum by default; preparation supplies a shasum-backed shim so the upstream archive digest is verified.'
        fi
    fi
    printf '%s\n' \
        "  The installer's PATH helper at $uv_bin_dir/env is kept source-only: it loses any exec delegation and its execute bit, so a bare env keeps resolving to /usr/bin/env." \
        '  The official installer and its downloads share the upstream trust boundary; Plasticine adds no independent signature.' \
        '  Python versions, uv tools, cache, credentials and project environments are not installed, inspected, or changed.' \
        "  Standalone selection does not edit shell startup; ensure $uv_bin_dir is on PATH or select shell too." \
        '  No shell completion is generated: interactive shell startup must not spawn uv.'
}

# The official installer writes $uv_bin_dir/env as a source-only PATH helper.
# Its directory is prepended to PATH, so an executable copy shadows /usr/bin/env,
# and an `exec` delegation replaces any shell that sources the file instead of
# only adjusting PATH. Restore those two installer invariants and leave the rest
# of the file alone: rewriting it would also discard the paths the installer
# chose for a custom UV_INSTALL_DIR.
plasticine_uv_restore_path_helper() {
    plasticine_uv_helper=$uv_bin_dir/env
    if [ ! -e "$plasticine_uv_helper" ] && [ ! -L "$plasticine_uv_helper" ]; then
        return 0
    fi
    if [ ! -f "$plasticine_uv_helper" ] || [ -L "$plasticine_uv_helper" ]; then
        plasticine_uv_error "the installer PATH helper must be a regular file: $plasticine_uv_helper; left untouched."
        return 1
    fi
    plasticine_uv_helper_changed=0
    if grep -Eq '^[[:space:]]*exec([[:space:]]|$)' "$plasticine_uv_helper"; then
        plasticine_uv_helper_clean=$uv_work/env.normalized
        grep -Ev '^[[:space:]]*exec([[:space:]]|$)' "$plasticine_uv_helper" > "$plasticine_uv_helper_clean" || return 1
        chmod 644 "$plasticine_uv_helper_clean" || return 1
        mv -f "$plasticine_uv_helper_clean" "$plasticine_uv_helper" || return 1
        plasticine_uv_helper_changed=1
    fi
    if [ -x "$plasticine_uv_helper" ]; then
        chmod 644 "$plasticine_uv_helper" || return 1
        plasticine_uv_helper_changed=1
    fi
    if [ "$plasticine_uv_helper_changed" -eq 1 ]; then
        plasticine_uv_log "uv: restored the source-only PATH helper at $plasticine_uv_helper (no exec delegation, not executable)."
    fi
}

plasticine_uv_prepare() (
    for plasticine_uv_command in curl tar mktemp rm mv sh awk sed grep mkdir chmod; do
        command -v "$plasticine_uv_command" >/dev/null 2>&1 || {
            plasticine_uv_error "missing required command: $plasticine_uv_command"
            return 1
        }
    done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        plasticine_uv_error 'archive verification needs sha256sum or shasum; install one and retry.'
        return 1
    fi
    uv_work=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-uv.XXXXXX") || return 1
    trap 'rm -rf "$uv_work"' EXIT
    trap 'exit 1' HUP INT TERM
    mkdir -p "$uv_work/bin" || return 1
    if ! command -v sha256sum >/dev/null 2>&1; then
        # The upstream installer verifies each archive with sha256sum but
        # silently skips verification when that command is absent (macOS).
        # Supply the documented digest through the platform shasum instead.
        cat > "$uv_work/bin/sha256sum" <<'SHIM'
#!/bin/sh
exec shasum -a 256 "$@"
SHIM
        chmod 755 "$uv_work/bin/sha256sum" || return 1
    fi

    case $uv_route in
        self-update)
            plasticine_uv_plan "$uv_dest" || return 1
            [ "$uv_route" = self-update ] || {
                plasticine_uv_error 'managed installation changed during preparation; retry from the observed state.'
                return 1
            }
            (
                HOME=$uv_dest
                UV_INSTALL_DIR=$uv_bin_dir
                UV_NO_MODIFY_PATH=1
                PATH=$uv_work/bin:$PATH
                export HOME UV_INSTALL_DIR UV_NO_MODIFY_PATH PATH
                unset UV_UNMANAGED_INSTALL UV_DISABLE_UPDATE
                "$uv_target" self update
            ) || {
                plasticine_uv_error 'uv self update failed; the existing installation is retained. Repair it and retry.'
                return 1
            } ;;
        install|repair)
            curl -fsSL -o "$uv_work/install.sh" https://astral.sh/uv/install.sh || {
                plasticine_uv_error 'official installer download failed; no installation attempted.'
                return 1
            }
            if ! grep -q '^APP_NAME="uv"' "$uv_work/install.sh" 2>/dev/null ||
                ! grep -q '^APP_VERSION="[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*"$' "$uv_work/install.sh" 2>/dev/null; then
                plasticine_uv_error 'downloaded file is not the reviewed uv installer; nothing changed.'
                return 1
            fi
            # Recheck after downloading and before the installer can write.
            plasticine_uv_plan "$uv_dest" || return 1
            case $uv_route in
                install)
                    [ "$uv_owner" = missing ] || {
                        plasticine_uv_error 'uv appeared during preparation; retry from its current state.'
                        return 1
                    } ;;
                repair)
                    [ "$uv_owner" = managed ] || [ "$uv_owner" = partial ] || {
                        plasticine_uv_error 'managed installation changed during preparation; retry from the observed state.'
                        return 1
                    } ;;
                *)
                    plasticine_uv_error 'managed installation changed during preparation; retry from the observed state.'
                    return 1 ;;
            esac
            (
                HOME=$uv_dest
                UV_INSTALL_DIR=$uv_bin_dir
                UV_NO_MODIFY_PATH=1
                PATH=$uv_work/bin:$PATH
                export HOME UV_INSTALL_DIR UV_NO_MODIFY_PATH PATH
                unset UV_UNMANAGED_INSTALL UV_DISABLE_UPDATE
                sh "$uv_work/install.sh"
            ) || {
                plasticine_uv_error 'official installer failed; partial native effects are retained. Repair and retry.'
                return 1
            } ;;
        *)
            plasticine_uv_error 'unsupported preparation route.'
            return 1 ;;
    esac

    plasticine_uv_validate_destination || return 1
    uv_final=$(plasticine_uv_version "$uv_target") || {
        plasticine_uv_error "uv failed its final health check at $uv_target; repair or remove it, then retry."
        return 1
    }
    uvx_final=$(plasticine_uv_version "$uvx_target") || {
        plasticine_uv_error "uvx failed its final health check at $uvx_target; repair or remove it, then retry."
        return 1
    }
    [ "$uv_final" = "$uvx_final" ] || {
        plasticine_uv_error "uv $uv_final and uvx $uvx_final differ after preparation; repair the installation and retry."
        return 1
    }
    [ -f "$uv_receipt" ] && [ ! -L "$uv_receipt" ] || {
        plasticine_uv_error "the installer did not write the updater receipt at $uv_receipt; self update would be unavailable. Repair or remove the installation, then retry."
        return 1
    }
    uv_prefix=$(plasticine_uv_receipt_prefix) || uv_prefix=''
    [ "$uv_prefix" = "$uv_bin_dir" ] || {
        plasticine_uv_error "the updater receipt does not point to $uv_bin_dir; repair or remove the installation, then retry."
        return 1
    }
    plasticine_uv_restore_path_helper || return 1
    plasticine_uv_log "uv: route=$uv_route; version=$uv_final; result=$uv_target."
)
