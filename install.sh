#!/bin/sh
set -eu

readonly_repo_url='https://github.com/Plasticine-Yang/plasticine-dotfiles.git'
readonly_release_base_url='https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/download'
# Empty in the source checkout. scripts/build-release.sh replaces this exact
# metadata with the immutable assets published by a GitHub Release.
readonly_repo_revision=''
readonly_release_version=''
readonly_source_sha256=''
readonly_plugins_sha256=''

error() {
    printf 'plasticine-dotfiles: %s\n' "$1" >&2
}

log() {
    printf 'plasticine-dotfiles: %s\n' "$1"
}

install_cli_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk 'NF == 2 {print tolower($1)}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk 'NF == 2 {print tolower($1)}'
    else
        error 'Cannot install the local command without sha256sum or shasum.'
        return 1
    fi
}

install_cli_real_directory() {
    install_cli_directory=$1
    if [ -L "$install_cli_directory" ] ||
        { [ -e "$install_cli_directory" ] && [ ! -d "$install_cli_directory" ]; }; then
        error "CLI install path is not a real directory: $install_cli_directory"
        return 1
    fi
    mkdir -p "$install_cli_directory"
}

install_release_cli() {
    [ -n "$readonly_release_version" ] || return 0
    install_cli_invocation_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || return 1
    if [ -f "$install_cli_invocation_dir/VERSION" ] &&
        [ ! -L "$install_cli_invocation_dir/VERSION" ] &&
        [ -x "$install_cli_invocation_dir/plasticine" ] &&
        [ -x "$install_cli_invocation_dir/self-update" ] &&
        [ "$(cat "$install_cli_invocation_dir/VERSION")" = "$readonly_release_version" ]; then
        return 0
    fi

    install_cli_prefix=$HOME/.local
    install_cli_bin=$install_cli_prefix/bin
    install_cli_root=$install_cli_prefix/share/plasticine
    install_cli_releases=$install_cli_root/releases
    install_cli_release=$install_cli_releases/$readonly_release_version
    install_cli_launcher=$install_cli_bin/plasticine
    install_cli_current=$install_cli_root/current
    install_cli_base_url=$readonly_release_base_url/$readonly_release_version

    for install_cli_directory in "$install_cli_prefix" "$install_cli_bin" \
        "$install_cli_prefix/share" "$install_cli_root" "$install_cli_releases"; do
        install_cli_real_directory "$install_cli_directory" || return 1
    done
    if [ -L "$install_cli_launcher" ] ||
        { [ -e "$install_cli_launcher" ] && [ ! -f "$install_cli_launcher" ]; }; then
        error "Refusing to overwrite unsafe command target: $install_cli_launcher"
        return 1
    fi
    if [ -e "$install_cli_current" ] && [ ! -L "$install_cli_current" ]; then
        error "Current CLI selector is not a symlink: $install_cli_current"
        return 1
    fi

    install_cli_stage=$(mktemp -d "$install_cli_root/.install.XXXXXX") || return 1
    install_cli_cleanup() { rm -rf "$install_cli_stage"; }
    trap install_cli_cleanup EXIT HUP INT TERM
    install_cli_archive=$install_cli_stage/plasticine-cli.tar.gz
    install_cli_sums=$install_cli_stage/SHA256SUMS
    if [ -n "${PLASTICINE_RELEASE_ASSET_DIR:-}" ]; then
        case $PLASTICINE_RELEASE_ASSET_DIR in
            /*) ;;
            *) error 'PLASTICINE_RELEASE_ASSET_DIR must be absolute.'; return 1 ;;
        esac
        for install_cli_asset in plasticine-cli.tar.gz SHA256SUMS; do
            install_cli_source=$PLASTICINE_RELEASE_ASSET_DIR/$install_cli_asset
            [ -f "$install_cli_source" ] && [ ! -L "$install_cli_source" ] || {
                error "Local Release asset is unavailable: $install_cli_source"
                return 1
            }
            cp "$install_cli_source" "$install_cli_stage/$install_cli_asset" || return 1
        done
    else
        for install_cli_asset in plasticine-cli.tar.gz SHA256SUMS; do
            curl --proto '=https' --proto-redir '=https' -fsSL \
                -o "$install_cli_stage/$install_cli_asset" \
                "$install_cli_base_url/$install_cli_asset" || {
                error "Release asset download failed: $install_cli_asset"
                return 1
            }
        done
    fi

    install_cli_expected=$(awk '
        $2 == "plasticine-cli.tar.gz" && NF == 2 && $1 ~ /^[0-9A-Fa-f]{64}$/ {
            digest=tolower($1); matches++
        }
        END { if (matches == 1) print digest; else exit 1 }
    ' "$install_cli_sums") || {
        error 'SHA256SUMS does not contain exactly one valid plasticine-cli.tar.gz entry.'
        return 1
    }
    install_cli_actual=$(install_cli_sha256 "$install_cli_archive") || return 1
    [ "$install_cli_actual" = "$install_cli_expected" ] || {
        error 'SHA-256 mismatch: plasticine-cli.tar.gz'
        return 1
    }

    install_cli_candidate=$install_cli_stage/package
    mkdir "$install_cli_candidate"
    tar -tzf "$install_cli_archive" | awk '
        $0 == "./" || $0 == "plasticine" || $0 == "./plasticine" ||
            $0 == "install.sh" || $0 == "./install.sh" ||
            $0 == "self-update" || $0 == "./self-update" ||
            $0 == "VERSION" || $0 == "./VERSION" { next }
        { exit 1 }
    ' || {
        error 'Release CLI package contains an unsafe or unexpected path.'
        return 1
    }
    tar -xzf "$install_cli_archive" -C "$install_cli_candidate" || {
        error 'Could not extract plasticine-cli.tar.gz.'
        return 1
    }
    [ "$(find "$install_cli_candidate" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4 ] &&
        [ "$(find "$install_cli_candidate" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 4 ] &&
        [ -x "$install_cli_candidate/plasticine" ] &&
        [ -x "$install_cli_candidate/install.sh" ] &&
        [ -x "$install_cli_candidate/self-update" ] &&
        [ -f "$install_cli_candidate/VERSION" ] && [ ! -L "$install_cli_candidate/VERSION" ] || {
        error 'Release CLI package layout is invalid.'
        return 1
    }
    [ "$(cat "$install_cli_candidate/VERSION")" = "$readonly_release_version" ] &&
        [ "$("$install_cli_candidate/plasticine" --version)" = "plasticine $readonly_release_version" ] || {
        error 'Release CLI package health check failed.'
        return 1
    }

    install_cli_launcher_stage=$install_cli_stage/launcher
    cat >"$install_cli_launcher_stage" <<'EOF'
#!/bin/sh
set -eu

plasticine_error() {
    printf 'plasticine: %s\n' "$1" >&2
}

launcher_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || {
    plasticine_error 'could not resolve the launcher directory.'
    exit 1
}
install_prefix=$(dirname -- "$launcher_dir")
current_package=$install_prefix/share/plasticine/current
package_cli=$current_package/plasticine

if [ ! -f "$package_cli" ] || [ ! -x "$package_cli" ]; then
    plasticine_error 'current version package is unavailable.'
    exit 1
fi

exec "$package_cli" "$@"
EOF
    chmod 755 "$install_cli_launcher_stage"
    if [ -e "$install_cli_launcher" ] &&
        ! cmp -s "$install_cli_launcher_stage" "$install_cli_launcher"; then
        error "Refusing to overwrite non-Plasticine command: $install_cli_launcher"
        return 1
    fi

    if [ -e "$install_cli_release" ] || [ -L "$install_cli_release" ]; then
        if ! { [ -d "$install_cli_release" ] && [ ! -L "$install_cli_release" ] &&
            [ -x "$install_cli_release/plasticine" ] &&
            [ -x "$install_cli_release/install.sh" ] &&
            [ -x "$install_cli_release/self-update" ] &&
            [ -f "$install_cli_release/VERSION" ] && [ ! -L "$install_cli_release/VERSION" ] &&
            [ "$(find "$install_cli_release" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4 ] &&
            [ "$(find "$install_cli_release" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 4 ] &&
            cmp -s "$install_cli_candidate/plasticine" "$install_cli_release/plasticine" &&
            cmp -s "$install_cli_candidate/install.sh" "$install_cli_release/install.sh" &&
            cmp -s "$install_cli_candidate/self-update" "$install_cli_release/self-update" &&
            cmp -s "$install_cli_candidate/VERSION" "$install_cli_release/VERSION"; }; then
            error "Existing CLI release is unsafe or invalid: $install_cli_release"
            return 1
        fi
    else
        mv "$install_cli_candidate" "$install_cli_release" || return 1
    fi

    if [ ! -e "$install_cli_launcher" ]; then
        install_cli_launcher_publish=$(mktemp "$install_cli_bin/.plasticine.XXXXXX") || return 1
        if ! cp "$install_cli_launcher_stage" "$install_cli_launcher_publish" ||
            ! chmod 755 "$install_cli_launcher_publish" ||
            ! mv "$install_cli_launcher_publish" "$install_cli_launcher"; then
            rm -f "$install_cli_launcher_publish"
            return 1
        fi
    fi
    chmod 755 "$install_cli_launcher" || return 1

    install_cli_current_stage=$install_cli_root/.current.$$
    [ ! -e "$install_cli_current_stage" ] && [ ! -L "$install_cli_current_stage" ] || {
        error "Temporary CLI selector already exists: $install_cli_current_stage"
        return 1
    }
    ln -s "releases/$readonly_release_version" "$install_cli_current_stage"
    install_cli_switch_status=0
    case $(uname -s) in
        Darwin) mv -fh "$install_cli_current_stage" "$install_cli_current" || install_cli_switch_status=$? ;;
        Linux) mv -fT "$install_cli_current_stage" "$install_cli_current" || install_cli_switch_status=$? ;;
    esac
    if [ "$install_cli_switch_status" -ne 0 ]; then
        rm -f "$install_cli_current_stage"
        error 'Could not switch the current CLI release.'
        return 1
    fi

    trap - EXIT HUP INT TERM
    install_cli_cleanup
    case :${PATH:-}: in
        *:"$install_cli_bin":*) log 'Installed command: plasticine' ;;
        *)
            log "Installed command: $install_cli_launcher"
            log "Add it to PATH for future shells: export PATH=\"$install_cli_bin:\$PATH\""
            ;;
    esac
}

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Interactive mode:
  install.sh

Non-interactive mode:
  install.sh -y [--git-config] [--github-ssh --github-ssh-key <path>] [--fnm] [--herdr] [--lazygit] [--neovim] [--shell] [--login-shell]

Options:
  -y, --yes                       Skip selection/confirmation; native credentials may still be required
      --git-config                Configure shared Git preferences and local override inclusion
      --github-ssh                Configure GitHub SSH
      --github-ssh-key <path>     Private key to copy to ~/.ssh/id_github
      --github-ssh-test           Test GitHub SSH after applying
      --replace-github-ssh-key    Allow replacement of a different existing key
      --herdr                     Install or update Herdr from its stable channel
      --lazygit                   Prepare Lazygit if missing and configure its alias
      --fnm                       Install or update fnm through the permitted platform route
      --neovim                    Install/update Neovim, configure it, and prepare plugins
      --shell                     Configure Zsh and install missing reviewed tools; leave login shell unchanged
      --login-shell               Set existing Zsh as the account login shell (may require a password)
  -h, --help                      Show this help
EOF
}

yes=0
git_config=0
github_ssh=0
github_ssh_key=''
github_ssh_test=0
replace_github_ssh_key=0
shell=0
login_shell=0
lazygit=0
fnm=0
neovim=0
herdr=0

while [ "$#" -gt 0 ]; do
    case $1 in
        -y|--yes) yes=1 ;;
        --git-config) git_config=1 ;;
        --github-ssh) github_ssh=1 ;;
        --github-ssh-key)
            [ "$#" -ge 2 ] || { error '--github-ssh-key requires a path.'; exit 2; }
            github_ssh_key=$2
            shift
            ;;
        --github-ssh-key=*) github_ssh_key=${1#*=} ;;
        --github-ssh-test) github_ssh_test=1 ;;
        --replace-github-ssh-key) replace_github_ssh_key=1 ;;
        --shell) shell=1 ;;
        --login-shell) login_shell=1 ;;
        --herdr) herdr=1 ;;
        --lazygit) lazygit=1 ;;
        --fnm) fnm=1 ;;
        --neovim) neovim=1 ;;
        -h|--help) usage; exit 0 ;;
        *) error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

case $(uname -s) in
    Darwin|Linux) ;;
    *) error 'Only macOS and Linux are supported.'; exit 1 ;;
esac

case ${HOME:-} in
    /*) ;;
    *) error 'HOME must be an absolute path.'; exit 1 ;;
esac

if [ "$(id -u)" -eq 0 ]; then
    error 'Run as the target user, not root.'
    exit 1
fi
if [ "$neovim" -eq 1 ] && { [ -n "${NVIM_APPNAME:-}" ] || [ -n "${XDG_CONFIG_HOME:-}" ]; }; then
    error 'neovim: NVIM_APPNAME and XDG_CONFIG_HOME are unsupported; managed configuration must be ~/.config/nvim.'
    exit 1
fi

for command_name in ssh ssh-keygen git; do
    command -v "$command_name" >/dev/null 2>&1 || {
        error "Required command not found: $command_name"
        exit 1
    }
done

if [ "$yes" -eq 0 ]; then
    if [ "$github_ssh" -eq 1 ] || [ -n "$github_ssh_key" ] ||
       [ "$github_ssh_test" -eq 1 ] || [ "$replace_github_ssh_key" -eq 1 ] ||
       [ "$shell" -eq 1 ] || [ "$lazygit" -eq 1 ] || [ "$fnm" -eq 1 ] ||
       [ "$neovim" -eq 1 ] || [ "$herdr" -eq 1 ] || [ "$git_config" -eq 1 ] ||
       [ "$login_shell" -eq 1 ]; then
        error 'Tool options require -y; run without options for interactive selection.'
        exit 2
    fi
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        error 'Interactive mode requires a terminal; use -y for automation.'
        exit 1
    fi
else
    if [ -n "$github_ssh_key" ] || [ "$github_ssh_test" -eq 1 ] || [ "$replace_github_ssh_key" -eq 1 ]; then
        [ "$github_ssh" -eq 1 ] || { error 'GitHub SSH options require --github-ssh.'; exit 2; }
    fi
    if [ "$github_ssh" -eq 1 ] && [ -z "$github_ssh_key" ]; then
        error '--github-ssh requires --github-ssh-key in non-interactive mode.'
        exit 2
    fi
fi

# A released bootstrap publishes its durable local command before the Owner
# confirms any Feature changes. Source-checkout installers have no immutable
# version metadata and intentionally remain development-only entrypoints.
install_release_cli || exit 1

[ -f "$(dirname -- "$0")/lib/chezmoi-bootstrap.sh" ] || { error 'The installer does not contain lib/chezmoi-bootstrap.sh.'; exit 1; }
# shellcheck disable=SC1091
. "$(dirname -- "$0")/lib/chezmoi-bootstrap.sh"
plasticine_chezmoi_bootstrap "$HOME" "${PLASTICINE_CHEZMOI_BIN:-}" || exit 1
# Assigned by plasticine_chezmoi_bootstrap from the sourced module.
# shellcheck disable=SC2154
: "${chezmoi_bin:?}"
[ -f "$(dirname -- "$0")/lib/release-payload.sh" ] || { error 'The installer does not contain lib/release-payload.sh.'; exit 1; }
# shellcheck disable=SC1091
. "$(dirname -- "$0")/lib/release-payload.sh"

source_dir=${PLASTICINE_CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}
config_file=${PLASTICINE_CHEZMOI_CONFIG_FILE:-$HOME/.config/chezmoi/chezmoi.toml}
state_file=${PLASTICINE_CHEZMOI_STATE_FILE:-$HOME/.config/chezmoi/chezmoistate.boltdb}
destination_dir=${PLASTICINE_CHEZMOI_DEST_DIR:-$HOME}
repo_url=${PLASTICINE_DOTFILES_REPO_URL:-$readonly_repo_url}
release_base_url=${PLASTICINE_RELEASE_BASE_URL:-$readonly_release_base_url/$readonly_release_version}

case $source_dir:$config_file:$state_file:$destination_dir in
    /*:/*:/*:/*) ;;
    *) error 'chezmoi paths must be absolute.'; exit 1 ;;
esac

if [ -n "$readonly_release_version" ] && [ -z "${PLASTICINE_DOTFILES_REPO_URL:-}" ]; then
    [ -n "$readonly_repo_revision" ] && [ -n "$readonly_source_sha256" ] && [ -n "$readonly_plugins_sha256" ] || {
        error 'Release payload metadata is incomplete.'
        exit 1
    }
    log "Restoring released chezmoi source: $readonly_repo_revision"
    plasticine_release_acquire_source "$HOME" "$release_base_url" "$readonly_release_version" \
        "$readonly_source_sha256" "$readonly_repo_revision" "$readonly_repo_url" "$source_dir" || exit 1
elif [ -e "$source_dir" ]; then
    if [ ! -d "$source_dir/.git" ] || [ -L "$source_dir" ]; then
        error "Existing chezmoi source is not a Git checkout: $source_dir"
        exit 1
    fi
    existing_repo=$(git -C "$source_dir" remote get-url origin 2>/dev/null || true)
    [ "$existing_repo" = "$repo_url" ] || {
        error "Existing chezmoi source belongs to another repository: $existing_repo"
        exit 1
    }
    [ -z "$(git -C "$source_dir" status --porcelain)" ] || {
        error "Existing chezmoi source has local changes: $source_dir"
        exit 1
    }
    if [ -n "$readonly_repo_revision" ]; then
        log "Selecting released chezmoi source: $readonly_repo_revision"
        if ! git -C "$source_dir" cat-file -e "$readonly_repo_revision^{commit}" 2>/dev/null; then
            git -C "$source_dir" fetch --no-tags origin "$readonly_repo_revision"
        fi
        [ "$(git -C "$source_dir" rev-parse "$readonly_repo_revision^{commit}")" = "$readonly_repo_revision" ] || {
            error "Release revision did not resolve to the expected commit: $readonly_repo_revision"
            exit 1
        }
        git -C "$source_dir" checkout --detach "$readonly_repo_revision"
    else
        log 'Updating chezmoi source...'
        git -C "$source_dir" pull --ff-only
    fi
else
    source_parent=$(dirname "$source_dir")
    mkdir -p "$source_parent"
    log 'Cloning chezmoi source...'
    git clone -- "$repo_url" "$source_dir"
    if [ -n "$readonly_repo_revision" ]; then
        [ "$(git -C "$source_dir" rev-parse "$readonly_repo_revision^{commit}")" = "$readonly_repo_revision" ] || {
            error "Release revision is unavailable from the repository: $readonly_repo_revision"
            exit 1
        }
        git -C "$source_dir" checkout --detach "$readonly_repo_revision"
    fi
fi

integration_catalog=$source_dir/.chezmoitemplates/zsh-integration-catalog
[ -f "$integration_catalog" ] || {
    error 'The source repository does not contain the Zsh integration catalog.'
    exit 1
}
integration_catalog_seen=' '
while IFS= read -r integration_name || [ -n "$integration_name" ]; do
    case $integration_name in
        shell|lazygit) ;;
        *) error "Invalid Zsh integration catalog entry: $integration_name"; exit 1 ;;
    esac
    case $integration_catalog_seen in
        *" $integration_name "*) error "Duplicate Zsh integration catalog entry: $integration_name"; exit 1 ;;
    esac
    integration_catalog_seen=$integration_catalog_seen$integration_name' '
done < "$integration_catalog"
[ "$integration_catalog_seen" = ' shell lazygit ' ] || {
    error 'The source Zsh integration catalog must contain exactly shell then lazygit.'
    exit 1
}

if [ "$yes" -eq 1 ]; then
    export PLASTICINE_NONINTERACTIVE=1
    tools=''
    if [ "$git_config" -eq 1 ]; then
        tools=git-config
    fi
    if [ "$github_ssh" -eq 1 ]; then
        tools="${tools:+$tools }github-ssh"
        export PLASTICINE_GITHUB_SSH_KEY="$github_ssh_key"
    else
        export PLASTICINE_GITHUB_SSH_KEY=''
    fi
    if [ "$shell" -eq 1 ]; then
        tools="${tools:+$tools }shell"
    fi
    if [ "$login_shell" -eq 1 ]; then
        tools="${tools:+$tools }login-shell"
    fi
    if [ "$lazygit" -eq 1 ]; then
        tools="${tools:+$tools }lazygit"
    fi
    if [ "$fnm" -eq 1 ]; then
        tools="${tools:+$tools }fnm"
    fi
    if [ "$neovim" -eq 1 ]; then
        tools="${tools:+$tools }neovim"
    fi
    if [ "$herdr" -eq 1 ]; then
        tools="${tools:+$tools }herdr"
    fi
    export PLASTICINE_TOOLS="$tools"
    export PLASTICINE_GITHUB_SSH_TEST=$github_ssh_test
    export PLASTICINE_REPLACE_GITHUB_SSH_KEY=$replace_github_ssh_key
else
    unset PLASTICINE_NONINTERACTIVE PLASTICINE_TOOLS PLASTICINE_GITHUB_SSH_KEY \
        PLASTICINE_GITHUB_SSH_TEST PLASTICINE_REPLACE_GITHUB_SSH_KEY
fi

[ -f "$source_dir/.chezmoi.toml.tmpl" ] || {
    error 'The source repository does not contain .chezmoi.toml.tmpl.'
    exit 1
}
if [ -L "$config_file" ] || { [ -e "$config_file" ] && [ ! -f "$config_file" ]; }; then
    error "chezmoi config is not a regular file: $config_file"
    exit 1
fi
config_parent=$(dirname "$config_file")
state_parent=$(dirname "$state_file")
mkdir -p "$config_parent" "$state_parent"
if [ "$yes" -eq 1 ]; then
    "$chezmoi_bin" \
        -S "$source_dir" \
        -D "$destination_dir" \
        --persistent-state "$state_file" \
        --no-tty \
        init -C "$config_file"
else
    "$chezmoi_bin" \
        -S "$source_dir" \
        -D "$destination_dir" \
        --persistent-state "$state_file" \
        init -C "$config_file"
fi
[ -s "$config_file" ] || { error 'Generated chezmoi config is empty.'; exit 1; }
chmod 600 "$config_file"

set -- -S "$source_dir" -D "$destination_dir" -c "$config_file" --persistent-state "$state_file"

shell_selected=0
login_shell_selected=0
lazygit_selected=0
fnm_selected=0
neovim_selected=0
herdr_selected=0
zsh_integration_selected=0
shell_antidote_route=''
shell_zsh=''
plasticine_release_plugins_path=''
if awk '/^[[:space:]]*tools = / { found = ($0 ~ /"shell"/); exit } END { exit !found }' "$config_file"; then
    shell_selected=1
fi
if awk '/^[[:space:]]*tools = / { found = ($0 ~ /"lazygit"/); exit } END { exit !found }' "$config_file"; then
    lazygit_selected=1
fi
if awk '/^[[:space:]]*tools = / { found = ($0 ~ /"fnm"/); exit } END { exit !found }' "$config_file"; then
    fnm_selected=1
fi
if awk '/^[[:space:]]*tools = / { found = ($0 ~ /"neovim"/); exit } END { exit !found }' "$config_file"; then
    neovim_selected=1
fi
if awk '/^[[:space:]]*tools = / { found = ($0 ~ /"herdr"/); exit } END { exit !found }' "$config_file"; then
    herdr_selected=1
fi
if awk '/^[[:space:]]*tools = / { found = ($0 ~ /"login-shell"/); exit } END { exit !found }' "$config_file"; then
    login_shell_selected=1
fi
if [ "$shell_selected" -eq 1 ] || [ "$lazygit_selected" -eq 1 ]; then
    zsh_integration_selected=1
fi

if [ -n "$readonly_release_version" ] && { [ "$shell_selected" -eq 1 ] || [ "$neovim_selected" -eq 1 ]; }; then
    # The released installer has this module inlined before source acquisition.
    # A local installer reaches the same interface from its source checkout.
    plasticine_release_acquire_plugins "$HOME" "$release_base_url" "$readonly_release_version" \
        "$readonly_plugins_sha256" || exit 1
    [ -n "$plasticine_release_plugins_path" ] || {
        error 'The managed plugin Release asset path is unavailable after acquisition.'
        exit 1
    }
    export PLASTICINE_MANAGED_PLUGINS_ARCHIVE="$plasticine_release_plugins_path"
else
    unset PLASTICINE_MANAGED_PLUGINS_ARCHIVE
fi

# Validate every selected Integration Block namespace before probing or
# preparing any selected tool. The same rendered module is run again by
# chezmoi immediately before apply to close the confirmation-time race.
if [ "$zsh_integration_selected" -eq 1 ]; then
    "$chezmoi_bin" "$@" execute-template \
        < "$source_dir/.chezmoiscripts/run_before_01_validate_zshrc_integrations.sh.tmpl" | /bin/sh
fi

if [ "$lazygit_selected" -eq 1 ]; then
    [ -f "$source_dir/lib/lazygit-bootstrap.sh" ] || {
        error 'The source repository does not contain lib/lazygit-bootstrap.sh.'
        exit 1
    }
    # shellcheck disable=SC1091
    . "$source_dir/lib/lazygit-bootstrap.sh"
    plasticine_lazygit_plan "$destination_dir" || exit 1
    log 'Previewing Lazygit toolchain...'
    plasticine_lazygit_preview
fi

if [ "$fnm_selected" -eq 1 ]; then
    [ -f "$source_dir/lib/fnm-bootstrap.sh" ] || {
        error 'The source repository does not contain lib/fnm-bootstrap.sh.'
        exit 1
    }
    # shellcheck disable=SC1091
    . "$source_dir/lib/fnm-bootstrap.sh"
    plasticine_fnm_plan "$destination_dir" || exit 1
    log 'Previewing fnm maintenance...'
    plasticine_fnm_preview
    # Assigned by plasticine_fnm_plan from the sourced module.
    # shellcheck disable=SC2154
    if [ "$fnm_os" = Darwin ] && [ "$fnm_brew_route" = bootstrap ] &&
        ! plasticine_fnm_terminal; then
        error 'fnm: Homebrew bootstrap needs a native terminal; install Homebrew interactively, then retry. --yes cannot supply credentials.'
        exit 1
    fi
fi

if [ "$herdr_selected" -eq 1 ]; then
    [ -f "$source_dir/lib/herdr-bootstrap.sh" ] || {
        error 'The source repository does not contain lib/herdr-bootstrap.sh.'
        exit 1
    }
    # shellcheck disable=SC1091
    . "$source_dir/lib/herdr-bootstrap.sh"
    plasticine_herdr_plan "$destination_dir" || exit 1
    log 'Previewing Herdr toolchain...'
    plasticine_herdr_preview
fi

if [ "$shell_selected" -eq 1 ]; then
    [ -f "$source_dir/lib/shell-bootstrap.sh" ] || {
        error 'The source repository does not contain lib/shell-bootstrap.sh.'
        exit 1
    }
    # shellcheck disable=SC1091
    . "$source_dir/lib/shell-bootstrap.sh"
    plasticine_shell_plan "$destination_dir" || exit 1
    log 'Previewing shell toolchain...'
    plasticine_shell_preview
    if [ "$shell_antidote_route" = brew-bootstrap ] && [ "$yes" -eq 1 ] &&
        ! plasticine_shell_terminal; then
        error 'shell: Homebrew bootstrap needs a native terminal; install Homebrew interactively, then retry. --yes cannot supply credentials.'
        exit 1
    fi
fi
if [ "$neovim_selected" -eq 1 ]; then
    [ -f "$source_dir/lib/neovim-bootstrap.sh" ] || {
        error 'The source repository does not contain lib/neovim-bootstrap.sh.'
        exit 1
    }
    # shellcheck disable=SC1091
    . "$source_dir/lib/neovim-bootstrap.sh"
    plasticine_neovim_plan "$destination_dir" || exit 1
    plasticine_neovim_preview || exit 1
fi

if [ "$login_shell_selected" -eq 1 ]; then
    [ -f "$source_dir/lib/login-shell-bootstrap.sh" ] || {
        error 'The source repository does not contain lib/login-shell-bootstrap.sh.'
        exit 1
    }
    # shellcheck disable=SC1091
    . "$source_dir/lib/login-shell-bootstrap.sh"
    if [ "$shell_selected" -eq 1 ]; then
        plasticine_login_shell_plan "$shell_zsh" || exit 1
    else
        plasticine_login_shell_plan || exit 1
    fi
    plasticine_login_shell_preview
fi

log 'Previewing changes...'
"$chezmoi_bin" "$@" --no-pager diff

if [ "$yes" -eq 0 ]; then
    printf 'Apply these changes? [y/N] '
    IFS= read -r answer
    case $answer in
        y|Y|yes|YES|Yes) ;;
        *) log 'Cancelled; no changes were applied.'; exit 0 ;;
    esac
fi

if [ "$shell_selected" -eq 1 ] && [ "$shell_antidote_route" = brew-bootstrap ] &&
    ! plasticine_shell_terminal; then
    error 'shell: Homebrew bootstrap needs a native terminal; install Homebrew interactively, then retry. --yes cannot supply credentials.'
    exit 1
fi

log 'Applying changes...'
if [ "$yes" -eq 1 ]; then
    "$chezmoi_bin" "$@" --no-tty --error-on-conflict apply
else
    "$chezmoi_bin" "$@" --error-on-conflict apply
fi
log 'Done.'
