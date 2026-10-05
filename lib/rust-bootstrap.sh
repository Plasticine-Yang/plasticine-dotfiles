#!/bin/sh
# Native commands deliberately override homes only inside subshells; planning
# continues to read the caller's original environment.
# shellcheck disable=SC2030,SC2031

plasticine_rust_error() {
    printf 'plasticine-dotfiles: rust: %s\n' "$1" >&2
}

# Inspect PATH entries, including broken/non-executable installations.
plasticine_rust_resolve() {
    plasticine_rust_path=$PATH
    while :; do
        plasticine_rust_dir=${plasticine_rust_path%%:*}
        [ -n "$plasticine_rust_dir" ] || plasticine_rust_dir=.
        if [ -e "$plasticine_rust_dir/$1" ] || [ -L "$plasticine_rust_dir/$1" ]; then
            printf '%s/%s\n' "$(cd -- "$plasticine_rust_dir" && pwd -P)" "$1"
            return 0
        fi
        case $plasticine_rust_path in *:*) plasticine_rust_path=${plasticine_rust_path#*:} ;; *) return 1 ;; esac
    done
}

plasticine_rust_validate_destination() {
    for plasticine_rust_parent in "$rust_dest" "$rust_cargo_home" "$rust_cargo_home/bin" "$rust_rustup_home"; do
        if [ -e "$plasticine_rust_parent" ] || [ -L "$plasticine_rust_parent" ]; then
            [ -d "$plasticine_rust_parent" ] && [ ! -L "$plasticine_rust_parent" ] || {
                plasticine_rust_error "native home/bin must be a real directory: $plasticine_rust_parent; left untouched."
                return 1
            }
        fi
    done
    if [ -e "$rust_bin" ] || [ -L "$rust_bin" ]; then
        [ -f "$rust_bin" ] && [ ! -L "$rust_bin" ] || {
            plasticine_rust_error "rustup must be a regular native executable: $rust_bin; repair its owner."
            return 1
        }
    fi
}

# Keep destination/native homes explicit even when chezmoi's HOME differs from
# destDir. Explicit toolchain commands ignore the caller's project override.
plasticine_rust_native() (
    HOME=$rust_dest
    CARGO_HOME=$rust_cargo_home
    RUSTUP_HOME=$rust_rustup_home
    RUSTUP_AUTO_INSTALL=0
    PATH=$rust_cargo_home/bin:$PATH
    export HOME CARGO_HOME RUSTUP_HOME RUSTUP_AUTO_INSTALL PATH
    unset RUSTUP_TOOLCHAIN
    "$rust_bin" "$@"
)

plasticine_rust_version() {
    plasticine_rust_version_output=$(plasticine_rust_native --version 2>/dev/null) || return 1
    printf '%s\n' "$plasticine_rust_version_output" | LC_ALL=C awk '
        NR == 1 && $1 == "rustup" && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ {version=$2}
        END {if (version != "") print version; else exit 1}
    '
}

plasticine_rust_default() {
    if rust_default_output=$(plasticine_rust_native default 2>&1); then
        case $rust_default_output in
            *' (default)') rust_default=${rust_default_output% (default)} ;;
            *) plasticine_rust_error 'could not identify the existing default toolchain; repair rustup settings.'; return 1 ;;
        esac
    else
        case $rust_default_output in
            *'error: no default toolchain is configured'*) rust_default=none ;;
            *) plasticine_rust_error 'could not read the existing default toolchain; repair rustup settings.'; return 1 ;;
        esac
    fi
}

plasticine_rust_plan() {
    rust_dest=$1
    rust_cargo_home=${CARGO_HOME:-$rust_dest/.cargo}
    rust_rustup_home=${RUSTUP_HOME:-$rust_dest/.rustup}
    for plasticine_rust_home in "$rust_dest" "$rust_cargo_home" "$rust_rustup_home"; do
        case $plasticine_rust_home in
            /*) ;;
            *) plasticine_rust_error 'destination, CARGO_HOME and RUSTUP_HOME must be absolute paths.'; return 1 ;;
        esac
    done
    rust_bin=$rust_cargo_home/bin/rustup
    plasticine_rust_validate_destination || return 1
    if [ -d "$rust_dest" ]; then rust_dest=$(cd -- "$rust_dest" && pwd -P) || return 1; fi
    if [ -d "$rust_cargo_home" ]; then rust_cargo_home=$(cd -- "$rust_cargo_home" && pwd -P) || return 1; fi
    if [ -d "$rust_rustup_home" ]; then rust_rustup_home=$(cd -- "$rust_rustup_home" && pwd -P) || return 1; fi
    rust_bin=$rust_cargo_home/bin/rustup
    rust_os=${PLASTICINE_RUST_OS:-$(uname -s)}
    rust_arch=${PLASTICINE_RUST_ARCH:-$(uname -m)}
    case $rust_os:$rust_arch in
        Darwin:arm64|Darwin:aarch64|Darwin:x86_64|Linux:arm64|Linux:aarch64|Linux:x86_64|Linux:amd64) ;;
        *) plasticine_rust_error "no reviewed route for $rust_os/$rust_arch."; return 1 ;;
    esac
    rust_path_bin=$(plasticine_rust_resolve rustup) || rust_path_bin=''
    if [ -n "$rust_path_bin" ] && [ "$rust_path_bin" != "$rust_bin" ]; then
        plasticine_rust_error "external rustup at $rust_path_bin; maintain it through its owner. No shadow installation."
        return 1
    fi
    rust_owner=missing
    rust_observed=missing
    rust_default=none
    if [ -e "$rust_bin" ]; then
        rust_owner=native
        [ -x "$rust_bin" ] || { plasticine_rust_error "rustup is not executable: $rust_bin"; return 1; }
        rust_observed=$(plasticine_rust_version) || { plasticine_rust_error 'native rustup is unhealthy or not stable; repair it before retrying.'; return 1; }
        plasticine_rust_default || return 1
    else
        if [ -e "$rust_rustup_home/settings.toml" ] || [ -L "$rust_rustup_home/settings.toml" ]; then
            plasticine_rust_error 'existing rustup settings without its native executable; repair rustup before retrying.'
            return 1
        fi
        # rustup-init installs proxies. Never overwrite an independent compiler
        # or Cargo, including a partial native install without rustup.
        for plasticine_rust_proxy in cargo rustc rustdoc rustfmt cargo-fmt clippy-driver cargo-clippy rust-analyzer rust-gdb rust-gdbgui rust-lldb; do
            if [ -e "$rust_cargo_home/bin/$plasticine_rust_proxy" ] || [ -L "$rust_cargo_home/bin/$plasticine_rust_proxy" ]; then
                plasticine_rust_error "existing proxy without rustup: $rust_cargo_home/bin/$plasticine_rust_proxy; repair its owner."
                return 1
            fi
        done
        for plasticine_rust_command in rustc cargo; do
            if plasticine_rust_existing=$(plasticine_rust_resolve "$plasticine_rust_command"); then
                plasticine_rust_error "existing $plasticine_rust_command at $plasticine_rust_existing without native rustup; repair its owner. No shadow installation."
                return 1
            fi
        done
    fi
}

plasticine_rust_preview() {
    printf 'plasticine-dotfiles: rust: platform=%s/%s; rustup=%s; owner=%s; default=%s\n' "$rust_os" "$rust_arch" "$rust_observed" "$rust_owner" "$rust_default"
    printf '%s\n' \
        '  After confirmation: install missing rustup from https://sh.rustup.rs with --no-modify-path --default-toolchain none, or run native rustup self update.' \
        '  Install/update stable with the minimal profile plus rustfmt and clippy, then verify rustc, cargo, rustfmt and clippy-driver.' \
        '  First installation defaults to stable; existing defaults, other toolchains, project overrides and Cargo configuration are retained.' \
        "  Native homes: CARGO_HOME=$rust_cargo_home; RUSTUP_HOME=$rust_rustup_home." \
        "  Standalone selection does not edit shell startup; add $rust_cargo_home/bin to PATH or select shell too." \
        '  Official installer and native downloads share the upstream trust boundary; Plasticine adds no independent signature.'
}

plasticine_rust_prepare() (
    for plasticine_rust_command in curl mktemp rm sh awk; do
        command -v "$plasticine_rust_command" >/dev/null 2>&1 || { plasticine_rust_error "missing required command: $plasticine_rust_command"; return 1; }
    done
    if [ "$rust_owner" = missing ]; then
        rust_work=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-rust.XXXXXX") || return 1
        trap 'rm -rf "$rust_work"' EXIT
        trap 'exit 1' HUP INT TERM
        curl -fsSL -o "$rust_work/install.sh" https://sh.rustup.rs || {
            plasticine_rust_error 'official installer download failed; no installation attempted.'; return 1
        }
        # Recheck after downloading and before the native installer can write.
        plasticine_rust_plan "$rust_dest" || return 1
        [ "$rust_owner" = missing ] || { plasticine_rust_error 'rustup appeared during preparation; retry from its current state.'; return 1; }
        HOME=$rust_dest CARGO_HOME=$rust_cargo_home RUSTUP_HOME=$rust_rustup_home \
            sh "$rust_work/install.sh" -y --no-modify-path --default-toolchain none --profile minimal || {
            plasticine_rust_error 'native installation failed; its partial effects are retained. Repair rustup and retry.'; return 1
        }
        plasticine_rust_validate_destination || return 1
        rust_observed=$(plasticine_rust_version) || { plasticine_rust_error 'installed rustup failed verification; inspect native homes and retry.'; return 1; }
        plasticine_rust_default || return 1
    else
        plasticine_rust_native self update || { plasticine_rust_error 'native rustup self update failed; repair its owner and retry.'; return 1; }
        rust_observed=$(plasticine_rust_version) || { plasticine_rust_error 'updated rustup failed verification; repair it and retry.'; return 1; }
    fi
    rust_saved_default=$rust_default
    plasticine_rust_native toolchain install stable --profile minimal --component rustfmt --component clippy --no-self-update || {
        plasticine_rust_error 'stable toolchain maintenance failed; native effects are retained for retry; selected configuration was not applied.'; return 1
    }
    # Native toolchain install can set a default when none is configured.
    # Restore an existing explicit none; only a first installation chooses stable.
    if [ "$rust_owner" = native ] && [ "$rust_saved_default" = none ]; then
        plasticine_rust_native default none || return 1
    elif [ "$rust_owner" = missing ] && [ "$rust_saved_default" = none ]; then
        plasticine_rust_native default stable || return 1
    fi
    plasticine_rust_default || return 1
    if [ "$rust_owner" = native ] && [ "$rust_default" != "$rust_saved_default" ]; then
        plasticine_rust_error 'default toolchain changed unexpectedly; inspect rustup settings before retrying.'; return 1
    fi
    for plasticine_rust_command in rustc cargo rustfmt clippy-driver; do
        plasticine_rust_native run stable "$plasticine_rust_command" --version || {
            plasticine_rust_error "stable $plasticine_rust_command verification failed; repair native toolchain and retry."; return 1
        }
    done
    printf 'plasticine-dotfiles: rust: rustup=%s; stable ready with Cargo/rustfmt/Clippy; default=%s\n' "$rust_observed" "$rust_default"
)
