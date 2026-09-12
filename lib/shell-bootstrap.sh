#!/bin/sh

plasticine_shell_error() {
    printf 'plasticine-dotfiles: shell: %s\n' "$1" >&2
}

plasticine_shell_resolve() {
    command -v "$1" 2>/dev/null && return 0
    plasticine_shell_remaining=$PATH
    while :; do
        plasticine_shell_directory=${plasticine_shell_remaining%%:*}
        [ -n "$plasticine_shell_directory" ] || plasticine_shell_directory=.
        if [ -e "$plasticine_shell_directory/$1" ] || [ -L "$plasticine_shell_directory/$1" ]; then
            printf '%s\n' "$plasticine_shell_directory/$1"
            return 0
        fi
        case $plasticine_shell_remaining in
            *:*) plasticine_shell_remaining=${plasticine_shell_remaining#*:} ;;
            *) return 1 ;;
        esac
    done
}

plasticine_shell_require() {
    for plasticine_shell_cmd do
        if command -v "$plasticine_shell_cmd" >/dev/null 2>&1; then
            continue
        fi
        if plasticine_shell_resolve "$plasticine_shell_cmd" >/dev/null 2>&1; then
            plasticine_shell_error "$plasticine_shell_cmd is present but not executable; repair its installation owner. Left untouched."
            return 1
        fi
        plasticine_shell_error "missing local command: $plasticine_shell_cmd"
        return 1
    done
}

plasticine_shell_terminal() {
    case ${PLASTICINE_SHELL_TTY:-} in
        1) return 0 ;;
        0) return 1 ;;
        '') (test -r /dev/tty && test -w /dev/tty && : </dev/tty) 2>/dev/null ;;
        *) return 1 ;;
    esac
}

# Native credential prompts must read the terminal; --yes never synthesizes them.
plasticine_shell_native() {
    case ${PLASTICINE_SHELL_TTY:-} in
        0) return 1 ;;
        1) "$@" ;;
        *) "$@" </dev/tty ;;
    esac
}

plasticine_shell_same_login() {
    [ "$1" = "$2" ] && return 0
    # Merged /usr on supported Linux ships both spellings of the same Zsh.
    case $shell_os:$1:$2 in
        Linux:/bin/zsh:/usr/bin/zsh | Linux:/usr/bin/zsh:/bin/zsh) return 0 ;;
    esac
    return 1
}

plasticine_shell_conventional_brew() {
    case $shell_arch in
        arm64 | aarch64) printf '%s\n' "${PLASTICINE_SHELL_HOMEBREW_ARM:-/opt/homebrew/bin/brew}" ;;
        *) printf '%s\n' "${PLASTICINE_SHELL_HOMEBREW_INTEL:-/usr/local/bin/brew}" ;;
    esac
}

plasticine_shell_system_zsh() {
    printf '%s\n' "${PLASTICINE_SHELL_SYSTEM_ZSH:-/bin/zsh}"
}

plasticine_shell_apt_zsh() {
    printf '%s\n' "${PLASTICINE_SHELL_APT_ZSH:-/usr/bin/zsh}"
}

plasticine_shell_platform() {
    plasticine_shell_require uname awk id || return $?
    if [ -n "${PLASTICINE_SHELL_OS:-}" ]; then
        shell_os=$PLASTICINE_SHELL_OS
    else
        shell_os=$(uname -s) || return 1
    fi
    if [ -n "${PLASTICINE_SHELL_ARCH:-}" ]; then
        shell_arch=$PLASTICINE_SHELL_ARCH
    else
        shell_arch=$(uname -m) || return 1
    fi
    case $shell_os:$shell_arch in
        Darwin:arm64 | Darwin:aarch64 | Darwin:x86_64 | Linux:arm64 | Linux:aarch64 | Linux:x86_64) ;;
        *)
            plasticine_shell_error 'no reviewed route for this platform/architecture.'
            return 1
            ;;
    esac
    shell_apt_supported=0
    shell_support=best-effort
    if [ "$shell_os" = Darwin ]; then
        if [ -n "${PLASTICINE_SHELL_MACOS_VERSION:-}" ]; then
            shell_version=$PLASTICINE_SHELL_MACOS_VERSION
        else
            plasticine_shell_require sw_vers || return $?
            shell_version=$(sw_vers -productVersion) || return 1
        fi
        shell_major=${shell_version%%.*}
        case $shell_major in
            '' | *[!0-9]*)
                plasticine_shell_error 'unable to read the macOS version.'
                return 1
                ;;
        esac
        [ "$shell_major" -ge 14 ] || {
            plasticine_shell_error 'reviewed macOS routes require macOS 14 or newer.'
            return 1
        }
        case $shell_major:$shell_arch in
            14:arm64 | 14:aarch64) shell_support=fully-supported ;;
        esac
    else
        # Parse OS metadata as data; never source executable /etc/os-release.
        shell_os_release=${PLASTICINE_SHELL_OS_RELEASE:-/etc/os-release}
        [ -f "$shell_os_release" ] || {
            plasticine_shell_error 'unable to read Linux distribution metadata.'
            return 1
        }
        shell_distribution=$(awk -F= '$1 == "ID" {gsub(/["'\'']/, "", $2); print $2}' "$shell_os_release") || return 1
        shell_version=$(awk -F= '$1 == "VERSION_ID" {gsub(/["'\'']/, "", $2); print $2}' "$shell_os_release") || return 1
        case $shell_distribution in
            debian | ubuntu)
                case $shell_version in
                    '' | *[!0-9.]* | .*)
                        plasticine_shell_error 'unable to read Linux distribution version.'
                        return 1
                        ;;
                esac
                if ! awk -v id="$shell_distribution" -v v="$shell_version" \
                    'BEGIN {exit !((id == "debian" && v+0 >= 13) || (id == "ubuntu" && v+0 >= 24.04))}'; then
                    plasticine_shell_error 'reviewed Linux routes require Debian 13 or Ubuntu 24.04 or newer.'
                    return 1
                fi
                shell_apt_supported=1
                case $shell_distribution:$shell_version in
                    debian:13 | ubuntu:24.04) shell_support=fully-supported ;;
                esac
                ;;
        esac
    fi
}

plasticine_shell_account() {
    case $shell_os in
        Linux)
            plasticine_shell_require getent || return $?
            shell_record=$(getent passwd "$(id -u)") || {
                plasticine_shell_error 'cannot read account login shell with getent.'
                return 1
            }
            shell_login=$(printf '%s\n' "$shell_record" | awk -F: 'NF == 7 {n++; s=$7} END {if (NR == 1 && n == 1) print s; else exit 1}') || {
                plasticine_shell_error 'invalid account login shell; inspect the native account database.'
                return 1
            }
            ;;
        Darwin)
            plasticine_shell_require dscl || return $?
            shell_user=$(id -un) || return 1
            case $shell_user in
                '' | *[!a-zA-Z0-9_.-]*)
                    plasticine_shell_error 'unable to read a safe account name for dscl.'
                    return 1
                    ;;
            esac
            shell_record=$(dscl . -read "/Users/$shell_user" UserShell) || {
                plasticine_shell_error 'cannot read account UserShell with dscl.'
                return 1
            }
            shell_login=$(printf '%s\n' "$shell_record" | awk '$1 == "UserShell:" && NF == 2 {n++; s=$2} END {if (NR == 1 && n == 1) print s; else exit 1}') || {
                plasticine_shell_error 'invalid account login shell; inspect the native account database.'
                return 1
            }
            ;;
        *)
            plasticine_shell_error 'cannot read the account login shell on this platform.'
            return 1
            ;;
    esac
    case $shell_login in
        /*) ;;
        *)
            plasticine_shell_error 'invalid account login shell; inspect the native account database.'
            return 1
            ;;
    esac
}

plasticine_shell_antidote_command() {
    # -f avoids Owner startup files; HOME/ANTIDOTE_HOME keep plugin state in dest.
    # shellcheck disable=SC2016
    HOME=$shell_dest_dir ANTIDOTE_HOME=$shell_dest_dir/.cache/antidote \
        "$shell_zsh" -f -c '. "$1" && shift && antidote "$@"' plasticine-shell "$shell_antidote" "$@"
}

plasticine_shell_antidote_health() {
    if [ -n "$shell_antidote" ] && [ -f "$shell_antidote" ] && [ -r "$shell_antidote" ] &&
        plasticine_shell_antidote_command --version >/dev/null 2>&1; then
        return 0
    fi
    plasticine_shell_error 'Antidote is present but unhealthy; repair its native checkout/Homebrew installation. Left untouched.'
    return 1
}

plasticine_shell_prompt_root() {
    printf '%s\n' "$shell_dest_dir/.cache/antidote/github.com/romkatv/powerlevel10k"
}

plasticine_shell_prompt_check() {
    shell_prompt_route=bundle
    shell_prompt=$(plasticine_shell_antidote_command path romkatv/powerlevel10k 2>/dev/null) || return 0
    case $shell_prompt in
        /*) ;;
        *)
            plasticine_shell_error 'invalid native Powerlevel10k path.'
            return 1
            ;;
    esac
    if [ -e "$shell_prompt" ] || [ -L "$shell_prompt" ]; then
        if [ -f "$shell_prompt/powerlevel10k.zsh-theme" ] && [ -r "$shell_prompt/powerlevel10k.zsh-theme" ] &&
            "$shell_zsh" -f -n "$shell_prompt/powerlevel10k.zsh-theme" >/dev/null 2>&1; then
            shell_prompt_route=existing
        else
            plasticine_shell_error 'Powerlevel10k is present but unhealthy; repair with Antidote. Left untouched.'
            return 1
        fi
    fi
}

# Filesystem-only when Zsh is not runnable yet (APT). Do not require Git for bundle.
plasticine_shell_prompt_from_cache() {
    shell_prompt=$(plasticine_shell_prompt_root)
    if [ ! -e "$shell_prompt" ] && [ ! -L "$shell_prompt" ]; then
        return 0
    fi
    if [ -f "$shell_prompt/powerlevel10k.zsh-theme" ] && [ -r "$shell_prompt/powerlevel10k.zsh-theme" ]; then
        shell_prompt_route=existing
        return 0
    fi
    plasticine_shell_error 'Powerlevel10k is present but unhealthy; repair with Antidote. Left untouched.'
    return 1
}

plasticine_shell_git_needed() {
    [ "$shell_antidote_route" != existing ] || [ "$shell_prompt_route" != existing ]
}

plasticine_shell_observe_git() {
    plasticine_shell_git_needed || return 0
    if [ "$shell_antidote_route" = brew-bootstrap ]; then
        # Homebrew's official installer obtains CLT/Git through its own prompts.
        return 0
    fi
    if [ "$shell_os" = Darwin ]; then
        plasticine_shell_require xcode-select || return $?
        xcode-select -p >/dev/null 2>&1 || {
            plasticine_shell_error 'Git requires Apple Command Line Tools; run xcode-select --install interactively, then retry.'
            return 1
        }
    fi
    if plasticine_shell_resolve git >/dev/null 2>&1; then
        git --version >/dev/null 2>&1 || {
            plasticine_shell_error 'Git is present but unhealthy; repair its installation owner. Left untouched.'
            return 1
        }
    elif [ "$shell_os" = Linux ]; then
        shell_apt_packages="${shell_apt_packages:+$shell_apt_packages }git ca-certificates"
    else
        plasticine_shell_error 'missing Apple Command Line Tools Git; repair CLT, then retry.'
        return 1
    fi
}

plasticine_shell_discover_antidote() {
    shell_antidote=''
    shell_antidote_route=existing
    shell_brew=''
    shell_prefix=''
    shell_brew_formulae=''
    if [ "$shell_os" = Linux ]; then
        if [ -e "$shell_dest_dir/.antidote" ] || [ -L "$shell_dest_dir/.antidote" ]; then
            shell_antidote=$shell_dest_dir/.antidote/antidote.zsh
            return 0
        fi
        shell_antidote=$shell_dest_dir/.antidote/antidote.zsh
        shell_antidote_route=git
        return 0
    fi
    # Darwin runtime loads Homebrew Antidote only; do not select ~/.antidote.
    if [ "${PLASTICINE_SHELL_HIDE_BREW:-}" = 1 ]; then
        shell_brew=''
    else
        shell_brew=$(plasticine_shell_resolve brew) || shell_brew=''
        if [ -z "$shell_brew" ]; then
            shell_brew=$(plasticine_shell_conventional_brew)
            [ -e "$shell_brew" ] || [ -L "$shell_brew" ] || shell_brew=''
        fi
    fi
    if [ -n "$shell_brew" ]; then
        case $shell_brew in
            /*) ;;
            *)
                plasticine_shell_error 'Homebrew requires an absolute executable path.'
                return 1
                ;;
        esac
        HOMEBREW_NO_ANALYTICS=1 "$shell_brew" --version >/dev/null 2>&1 || {
            plasticine_shell_error 'Homebrew is present but unhealthy; repair its native installation. Left untouched.'
            return 1
        }
        shell_prefix=$(HOMEBREW_NO_ANALYTICS=1 "$shell_brew" --prefix antidote 2>/dev/null) || {
            plasticine_shell_error 'Homebrew Antidote discovery failed; repair Homebrew. No fallback.'
            return 1
        }
        case $shell_prefix in
            /*) ;;
            *)
                plasticine_shell_error 'Homebrew Antidote discovery failed; repair Homebrew. No fallback.'
                return 1
                ;;
        esac
        shell_antidote=$shell_prefix/share/antidote/antidote.zsh
        if [ ! -e "$shell_prefix" ] && [ ! -L "$shell_prefix" ]; then
            shell_antidote_route=brew
        fi
    else
        shell_antidote=''
        shell_antidote_route=brew-bootstrap
        plasticine_shell_require curl bash || return $?
    fi
    [ "$shell_antidote_route" = existing ] || shell_brew_formulae=antidote
}

plasticine_shell_plan() {
    shell_dest_dir=$1
    case $shell_dest_dir in
        /*) ;;
        *)
            plasticine_shell_error 'destination must be an absolute path.'
            return 1
            ;;
    esac
    shell_apt_packages=''
    shell_brew_formulae=''
    shell_brew=''
    shell_prefix=''
    shell_zsh=''
    shell_zsh_route=existing
    shell_antidote=''
    shell_antidote_route=existing
    shell_prompt=''
    shell_prompt_route=bundle
    shell_login=''
    shell_transition=0
    plasticine_shell_platform || return $?
    if [ "$shell_os" = Darwin ]; then
        # macOS login shell is the system copy; PATH/Homebrew Zsh must not shadow it.
        shell_zsh=$(plasticine_shell_system_zsh)
        shell_zsh_route=system
    elif [ "${PLASTICINE_SHELL_HIDE_ZSH:-}" = 1 ]; then
        shell_zsh=''
    elif [ "${PLASTICINE_SHELL_ZSH+set}" = set ]; then
        shell_zsh=$PLASTICINE_SHELL_ZSH
    else
        shell_zsh=$(plasticine_shell_resolve zsh) || shell_zsh=''
    fi
    if [ -z "$shell_zsh" ]; then
        shell_zsh=$(plasticine_shell_apt_zsh)
        shell_zsh_route=apt
        shell_apt_packages=zsh
    fi
    case $shell_zsh in
        /*) ;;
        *)
            plasticine_shell_error 'Zsh needs an absolute executable path for native chsh; repair PATH and retry.'
            return 1
            ;;
    esac
    if [ "$shell_zsh_route" != apt ]; then
        "$shell_zsh" --version >/dev/null 2>&1 || {
            plasticine_shell_error 'Zsh is present but unhealthy or system Zsh is missing; repair its existing installation owner. Left untouched.'
            return 1
        }
    fi
    plasticine_shell_discover_antidote || return $?
    if [ "$shell_antidote_route" = existing ]; then
        [ -f "$shell_antidote" ] && [ -r "$shell_antidote" ] || {
            plasticine_shell_error 'Antidote is present but unhealthy; repair its native installation. Left untouched.'
            return 1
        }
        if [ "$shell_zsh_route" != apt ]; then
            plasticine_shell_antidote_health || return 1
            plasticine_shell_prompt_check || return 1
        else
            plasticine_shell_prompt_from_cache || return 1
        fi
    fi
    plasticine_shell_observe_git || return $?
    if [ -n "$shell_apt_packages" ]; then
        [ "$shell_apt_supported" -eq 1 ] || {
            plasticine_shell_error 'no reviewed APT route for this Linux distribution; no Linux Homebrew or fallback.'
            return 1
        }
        plasticine_shell_require apt-get sudo || return $?
    fi
    plasticine_shell_account || return $?
    shell_transition=1
    plasticine_shell_same_login "$shell_login" "$shell_zsh" && shell_transition=0
    [ "$shell_transition" -eq 0 ] || plasticine_shell_require chsh || return $?
}

plasticine_shell_preview() {
    printf 'plasticine-dotfiles: shell: platform %s/%s (%s); Zsh route: %s; Antidote route: %s\n' \
        "$shell_os" "$shell_arch" "$shell_support" "$shell_zsh_route" "$shell_antidote_route"
    if [ -z "$shell_apt_packages" ] && [ -z "$shell_brew_formulae" ] &&
        [ "$shell_antidote_route" = existing ] && [ "$shell_prompt_route" = existing ] &&
        [ "$shell_transition" -eq 0 ]; then
        printf '%s\n' '  Existing healthy tools keep their native installation owners; health only; network: none; privilege: none.'
    else
        printf '%s\n' '  Existing healthy tools keep their native installation owners.'
    fi
    if [ "$shell_zsh_route" = system ]; then
        printf '  command: %s --version (macOS system copy; no installation)\n' "$shell_zsh"
    fi
    if [ -n "$shell_apt_packages" ]; then
        printf '%s\n' '  route: reviewed APT control-plane/Zsh packages; network: configured APT repositories; privilege: sudo only for these APT children' \
            "  command: sudo apt-get update" \
            "  command: sudo apt-get install -y --no-upgrade $shell_apt_packages" \
            '  Without a terminal: sudo -n for the same APT children; native credential requests cannot be answered by --yes.'
    fi
    case $shell_antidote_route in
        git)
            printf '%s\n' "  command: git clone --depth=1 https://github.com/mattmc3/antidote.git $shell_dest_dir/.antidote; network: HTTPS; privilege: none"
            ;;
        brew-bootstrap)
            printf '%s\n' '  Homebrew missing: official bootstrap; network: HTTPS; native terminal required.' \
                '  command: curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' \
                '  command: bash -c <official Homebrew installer>; invoking user, never sudo bash' \
                '  Homebrew itself may request administrator credentials/privilege and Apple Command Line Tools; --yes does not answer native prompts.'
            ;;
    esac
    if [ -n "$shell_brew_formulae" ]; then
        printf '%s\n' "  command: HOMEBREW_NO_ANALYTICS=1 brew install $shell_brew_formulae; network: HTTPS" \
            '  Homebrew itself may request administrator credentials/privilege; Plasticine does not wrap sudo brew; --yes does not answer native prompts.'
    fi
    if [ "$shell_prompt_route" = existing ]; then
        printf '%s\n' '  Powerlevel10k: already-present (native Antidote path, readable theme, syntax health); no update.'
    else
        printf '%s\n' '  Powerlevel10k route: documented Antidote plugin bundle (if missing after Zsh/Antidote preparation); network: HTTPS to GitHub; privilege: none' \
            '  command: zsh -f; source <native antidote.zsh>; antidote bundle romkatv/powerlevel10k kind:clone' \
            '  No plugin code or Owner plugin list is loaded; Antidote owns native clone/cache paths.'
    fi
    printf '%s\n' '  Upstream installer effects are partly opaque; no automatic fallback.' \
        '  Other managed/optional plugins load through Antidote at Zsh startup, not during installation.'
    if [ "$shell_transition" -eq 1 ]; then
        printf '  LAST, after usable configuration: chsh -s "%s" (native account login shell; not SHELL).\n' "$shell_zsh"
        printf '%s\n' '  Native terminal/password may be required; never sudo chsh or edit /etc/shells; --yes supplies no credentials.' \
            '  Failed/no-terminal transition leaves installed tools/configuration usable and marks shell failed; rerun in a terminal.'
    else
        printf '%s\n' '  Account login shell already correct; no chsh call (SHELL environment ignored).'
    fi
}

plasticine_shell_apt_install() {
    if plasticine_shell_terminal; then
        # shellcheck disable=SC2086
        plasticine_shell_native sudo apt-get update &&
            plasticine_shell_native sudo apt-get install -y --no-upgrade $shell_apt_packages
    else
        # shellcheck disable=SC2086
        sudo -n apt-get update &&
            sudo -n apt-get install -y --no-upgrade $shell_apt_packages
    fi || {
        plasticine_shell_error 'APT batch failed. Repair through APT; if credentials are needed rerun in a native terminal. --yes supplies no credentials. No fallback.'
        return 1
    }
}

plasticine_shell_refresh_brew_antidote() {
    shell_prefix=$(HOMEBREW_NO_ANALYTICS=1 "$shell_brew" --prefix antidote) || {
        plasticine_shell_error 'Homebrew Antidote discovery failed after install; repair Homebrew. No fallback.'
        return 1
    }
    case $shell_prefix in
        /*) ;;
        *)
            plasticine_shell_error 'Homebrew Antidote discovery failed after install; repair Homebrew. No fallback.'
            return 1
            ;;
    esac
    shell_antidote=$shell_prefix/share/antidote/antidote.zsh
}

plasticine_shell_brew_bootstrap() {
    if ! plasticine_shell_terminal; then
        plasticine_shell_error 'Homebrew bootstrap needs a native terminal; install Homebrew interactively, then retry. --yes cannot supply credentials.'
        return 1
    fi
    plasticine_shell_require curl bash || return $?
    shell_installer=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || {
        plasticine_shell_error 'official Homebrew installer download failed; no shell execution, fallback, or configuration.'
        return 1
    }
    if ! (
        unset NONINTERACTIVE CI
        HOMEBREW_NO_ANALYTICS=1
        export HOMEBREW_NO_ANALYTICS
        case ${PLASTICINE_SHELL_TTY:-} in
            1) bash -c "$shell_installer" ;;
            *) bash -c "$shell_installer" </dev/tty ;;
        esac
    ); then
        plasticine_shell_error 'official Homebrew installer failed; repair Homebrew. No fallback.'
        return 1
    fi
    shell_brew=$(plasticine_shell_resolve brew) || shell_brew=''
    if [ -z "$shell_brew" ]; then
        shell_brew=$(plasticine_shell_conventional_brew)
    fi
    case $shell_brew in
        /*) ;;
        *)
            plasticine_shell_error 'official Homebrew installer did not produce an absolute brew path. No fallback.'
            return 1
            ;;
    esac
    if [ ! -x "$shell_brew" ] || ! HOMEBREW_NO_ANALYTICS=1 "$shell_brew" --version >/dev/null 2>&1; then
        plasticine_shell_error 'official Homebrew installer did not produce a usable brew. No fallback.'
        return 1
    fi
}

plasticine_shell_prepare() {
    if [ -n "$shell_apt_packages" ]; then
        plasticine_shell_apt_install || return 1
        hash -r
        if [ "$shell_zsh_route" = apt ]; then
            if [ ! -x "$shell_zsh" ] || ! "$shell_zsh" --version >/dev/null 2>&1; then
                plasticine_shell_error 'reviewed APT route did not provide a healthy Zsh; repair through APT. No fallback.'
                return 1
            fi
        fi
    fi
    case $shell_antidote_route in
        git)
            git --version >/dev/null 2>&1 || {
                plasticine_shell_error 'Git is present but unhealthy; repair its installation owner. Left untouched.'
                return 1
            }
            git clone --depth=1 https://github.com/mattmc3/antidote.git "$shell_dest_dir/.antidote" || {
                plasticine_shell_error 'official Antidote Git checkout failed; no fallback or configuration applied.'
                return 1
            }
            shell_antidote=$shell_dest_dir/.antidote/antidote.zsh
            ;;
        brew)
            HOMEBREW_NO_ANALYTICS=1 "$shell_brew" install antidote || {
                plasticine_shell_error 'reviewed Homebrew route did not provide a healthy Antidote; repair through Homebrew. No fallback.'
                return 1
            }
            plasticine_shell_refresh_brew_antidote || return 1
            ;;
        brew-bootstrap)
            plasticine_shell_brew_bootstrap || return 1
            HOMEBREW_NO_ANALYTICS=1 "$shell_brew" install antidote || {
                plasticine_shell_error 'reviewed Homebrew route did not provide a healthy Antidote; repair through Homebrew. No fallback.'
                return 1
            }
            plasticine_shell_refresh_brew_antidote || return 1
            ;;
        existing) ;;
        *)
            plasticine_shell_error 'unknown Antidote route; no fallback.'
            return 1
            ;;
    esac
    if [ -z "$shell_zsh" ] || ! "$shell_zsh" --version >/dev/null 2>&1; then
        plasticine_shell_error 'Zsh is still unhealthy after preparation; no configuration applied.'
        return 1
    fi
    plasticine_shell_antidote_health || return 1
    plasticine_shell_prompt_check || return 1
    if [ "$shell_prompt_route" != existing ]; then
        git --version >/dev/null 2>&1 || {
            plasticine_shell_error 'Git is present but unhealthy; repair its installation owner. Left untouched.'
            return 1
        }
        plasticine_shell_antidote_command bundle romkatv/powerlevel10k kind:clone >/dev/null || {
            plasticine_shell_error 'Antidote did not obtain Powerlevel10k; no fallback or configuration applied.'
            return 1
        }
        plasticine_shell_prompt_check || return 1
        [ "$shell_prompt_route" = existing ] || {
            plasticine_shell_error 'Antidote did not produce a usable Powerlevel10k plugin; no configuration applied.'
            return 1
        }
    fi
}

plasticine_shell_transition() {
    [ "$shell_transition" -eq 1 ] || return 0
    case $shell_zsh in
        /*) ;;
        *)
            plasticine_shell_error 'Zsh needs an absolute executable path for native chsh.'
            return 1
            ;;
    esac
    plasticine_shell_account || return 1
    plasticine_shell_same_login "$shell_login" "$shell_zsh" && return 0
    if ! plasticine_shell_terminal; then
        plasticine_shell_error 'configuration is usable; chsh needs a native terminal. Rerun install.sh --shell in a terminal; --yes cannot provide credentials.'
        return 1
    fi
    plasticine_shell_native chsh -s "$shell_zsh" || {
        plasticine_shell_error 'chsh failed; installed tools and usable configuration retained. Retry in a native terminal; inspect account policy and /etc/shells manually.'
        return 1
    }
    plasticine_shell_account || return 1
    plasticine_shell_same_login "$shell_login" "$shell_zsh" || {
        plasticine_shell_error 'chsh did not update the account login shell; configuration retained. Inspect native account policy and retry.'
        return 1
    }
}
