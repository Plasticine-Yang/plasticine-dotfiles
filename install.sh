#!/bin/sh
set -eu

readonly_repo_url='https://github.com/Plasticine-Yang/plasticine-dotfiles.git'
readonly_chezmoi_version='v2.72.1'
# Empty in the source checkout. scripts/build-release.sh replaces this exact
# assignment with the full commit published by a GitHub Release.
readonly_repo_revision=''

error() {
    printf 'plasticine-dotfiles: %s\n' "$1" >&2
}

log() {
    printf 'plasticine-dotfiles: %s\n' "$1"
}

usage() {
    cat <<'EOF'
Usage: install.sh [options]

Interactive mode:
  install.sh

Non-interactive mode:
  install.sh -y [--github-ssh --github-ssh-key <path>] [--shell]

Options:
  -y, --yes                       Run without prompts and apply changes
      --github-ssh                Configure GitHub SSH
      --github-ssh-key <path>     Private key to copy to ~/.ssh/id_github
      --github-ssh-test           Test GitHub SSH after applying
      --replace-github-ssh-key    Allow replacement of a different existing key
      --shell                     Configure Zsh, install missing reviewed tools, and attempt chsh last
  -h, --help                      Show this help
EOF
}

chezmoi_is_compatible() {
    "$1" --version 2>/dev/null | awk '{
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^v[0-9]+\.[0-9]+\.[0-9]+/) {
                sub(/^v/, "", $i)
                sub(/[^0-9.].*$/, "", $i)
                version = $i
                break
            }
        }
    }
    END {
        if (version == "") exit 1
        split(version, part, /\./)
        if (part[1] > 2 ||
            (part[1] == 2 && part[2] > 72) ||
            (part[1] == 2 && part[2] == 72 && part[3] >= 1)) exit 0
        exit 1
    }'
}

yes=0
github_ssh=0
github_ssh_key=''
github_ssh_test=0
replace_github_ssh_key=0
shell=0

while [ "$#" -gt 0 ]; do
    case $1 in
        -y|--yes) yes=1 ;;
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

for command_name in ssh ssh-keygen git; do
    command -v "$command_name" >/dev/null 2>&1 || {
        error "Required command not found: $command_name"
        exit 1
    }
done

if [ "$yes" -eq 0 ]; then
    if [ "$github_ssh" -eq 1 ] || [ -n "$github_ssh_key" ] ||
       [ "$github_ssh_test" -eq 1 ] || [ "$replace_github_ssh_key" -eq 1 ] ||
       [ "$shell" -eq 1 ]; then
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

chezmoi_bin=${PLASTICINE_CHEZMOI_BIN:-}
if [ -n "$chezmoi_bin" ]; then
    case $chezmoi_bin in
        */*) ;;
        *) chezmoi_bin=$(command -v "$chezmoi_bin" 2>/dev/null || true) ;;
    esac
fi
if [ -z "$chezmoi_bin" ] && command -v chezmoi >/dev/null 2>&1; then
    chezmoi_bin=$(command -v chezmoi)
fi
if [ -n "$chezmoi_bin" ] && ! chezmoi_is_compatible "$chezmoi_bin"; then
    log "Ignoring incompatible chezmoi: $chezmoi_bin"
    chezmoi_bin=''
fi
if [ -z "$chezmoi_bin" ]; then
    command -v curl >/dev/null 2>&1 || { error 'curl is required to install chezmoi.'; exit 1; }
    install_bin_dir=$HOME/.local/bin
    log "Installing chezmoi $readonly_chezmoi_version to $install_bin_dir..."
    sh -c "$(curl --proto '=https' --proto-redir '=https' -fsSL https://get.chezmoi.io)" -- \
        -b "$install_bin_dir" -t "$readonly_chezmoi_version"
    chezmoi_bin=$install_bin_dir/chezmoi
fi
[ -x "$chezmoi_bin" ] || { error "chezmoi is not executable: $chezmoi_bin"; exit 1; }
chezmoi_is_compatible "$chezmoi_bin" || { error 'Installed chezmoi version is incompatible.'; exit 1; }

source_dir=${PLASTICINE_CHEZMOI_SOURCE_DIR:-$HOME/.local/share/chezmoi}
config_file=${PLASTICINE_CHEZMOI_CONFIG_FILE:-$HOME/.config/chezmoi/chezmoi.toml}
state_file=${PLASTICINE_CHEZMOI_STATE_FILE:-$HOME/.config/chezmoi/chezmoistate.boltdb}
destination_dir=${PLASTICINE_CHEZMOI_DEST_DIR:-$HOME}
repo_url=${PLASTICINE_DOTFILES_REPO_URL:-$readonly_repo_url}

case $source_dir:$config_file:$state_file:$destination_dir in
    /*:/*:/*:/*) ;;
    *) error 'chezmoi paths must be absolute.'; exit 1 ;;
esac

if [ -e "$source_dir" ]; then
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

if [ "$yes" -eq 1 ]; then
    export PLASTICINE_NONINTERACTIVE=1
    tools=''
    if [ "$github_ssh" -eq 1 ]; then
        tools=github-ssh
        export PLASTICINE_GITHUB_SSH_KEY="$github_ssh_key"
    else
        export PLASTICINE_GITHUB_SSH_KEY=''
    fi
    if [ "$shell" -eq 1 ]; then
        tools="${tools:+$tools }shell"
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
shell_antidote_route=''
if awk '/^[[:space:]]*tools = / { found = ($0 ~ /"shell"/); exit } END { exit !found }' "$config_file"; then
    shell_selected=1
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
