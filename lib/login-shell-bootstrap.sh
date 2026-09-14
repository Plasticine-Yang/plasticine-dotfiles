#!/bin/sh

plasticine_login_shell_error() {
    printf 'plasticine-dotfiles: login-shell: %s\n' "$1" >&2
}

plasticine_login_shell_account() {
    case $login_shell_os in
        Linux)
            login_shell_record=$(getent passwd "$(id -u)") || {
                plasticine_login_shell_error 'cannot read account login shell with getent.'
                return 1
            }
            login_shell_current=$(printf '%s\n' "$login_shell_record" | awk -F: 'NF == 7 {n++; s=$7} END {if (NR == 1 && n == 1) print s; else exit 1}') || {
                plasticine_login_shell_error 'invalid account login shell; inspect the native account database.'
                return 1
            }
            ;;
        Darwin)
            login_shell_user=$(id -un) || return 1
            case $login_shell_user in
                '' | *[!a-zA-Z0-9_.-]*)
                    plasticine_login_shell_error 'unable to read a safe account name for dscl.'
                    return 1
                    ;;
            esac
            login_shell_record=$(dscl . -read "/Users/$login_shell_user" UserShell) || {
                plasticine_login_shell_error 'cannot read account UserShell with dscl.'
                return 1
            }
            login_shell_current=$(printf '%s\n' "$login_shell_record" | awk '$1 == "UserShell:" && NF == 2 {n++; s=$2} END {if (NR == 1 && n == 1) print s; else exit 1}') || {
                plasticine_login_shell_error 'invalid account login shell; inspect the native account database.'
                return 1
            }
            ;;
    esac
    case $login_shell_current in
        /*) ;;
        *)
            plasticine_login_shell_error 'invalid account login shell; inspect the native account database.'
            return 1
            ;;
    esac
}

plasticine_login_shell_current() {
    [ "$login_shell_current" = "$login_shell_zsh" ] && return 0
    # Merged /usr on supported Linux ships both spellings of the same Zsh.
    case $login_shell_os:$login_shell_current:$login_shell_zsh in
        Linux:/bin/zsh:/usr/bin/zsh | Linux:/usr/bin/zsh:/bin/zsh) return 0 ;;
    esac
    return 1
}

plasticine_login_shell_plan() {
    login_shell_os=${PLASTICINE_LOGIN_SHELL_OS:-$(uname -s)}
    case $login_shell_os in
        Darwin) login_shell_zsh=/bin/zsh ;;
        Linux) login_shell_zsh=$(command -v zsh) || login_shell_zsh='' ;;
        *)
            plasticine_login_shell_error 'only macOS and Linux are supported.'
            return 1
            ;;
    esac
    if [ "${PLASTICINE_LOGIN_SHELL_ZSH+set}" = set ]; then
        login_shell_zsh=$PLASTICINE_LOGIN_SHELL_ZSH
    fi
    if [ -n "${1:-}" ]; then
        login_shell_zsh=$1
    fi
    case $login_shell_zsh in
        /*) ;;
        *)
            plasticine_login_shell_error 'Zsh needs an absolute executable path; install Zsh first or also select shell.'
            return 1
            ;;
    esac
    # A combined preview can name the Zsh that shell will install before apply.
    if [ -z "${1:-}" ] || [ -e "$login_shell_zsh" ] || [ -L "$login_shell_zsh" ]; then
        "$login_shell_zsh" --version >/dev/null 2>&1 || {
            plasticine_login_shell_error 'Zsh is missing or unhealthy; install or repair it first, or also select shell.'
            return 1
        }
    fi
    plasticine_login_shell_account || return 1
    if ! plasticine_login_shell_current; then
        command -v chsh >/dev/null 2>&1 || {
            plasticine_login_shell_error 'missing local command: chsh.'
            return 1
        }
    fi
}

plasticine_login_shell_preview() {
    printf 'plasticine-dotfiles: login-shell: account %s; target %s\n' "$login_shell_current" "$login_shell_zsh"
    if plasticine_login_shell_current; then
        printf '%s\n' '  Account login shell already correct; no chsh call (SHELL environment ignored).'
    else
        printf '  LAST, after selected configuration: chsh -s "%s"\n' "$login_shell_zsh"
        printf '%s\n' '  Native terminal/password may be required; never sudo chsh or edit /etc/shells; --yes supplies no credentials.' \
            '  No tool installation or configuration changes; a failed transition returns an error and retains existing tools/configuration.'
    fi
}

plasticine_login_shell_apply() {
    plasticine_login_shell_account || return 1
    plasticine_login_shell_current && return 0
    case ${PLASTICINE_LOGIN_SHELL_TTY:-} in
        1) ;;
        0) plasticine_login_shell_error 'chsh needs a native terminal; retry with --login-shell in a terminal; --yes cannot provide credentials.'; return 1 ;;
        *)
            if ! (test -r /dev/tty && test -w /dev/tty && : </dev/tty) 2>/dev/null; then
                plasticine_login_shell_error 'chsh needs a native terminal; retry with --login-shell in a terminal; --yes cannot provide credentials.'
                return 1
            fi
            ;;
    esac
    if [ "${PLASTICINE_LOGIN_SHELL_TTY:-}" = 1 ]; then
        chsh -s "$login_shell_zsh" && login_shell_status=0 || login_shell_status=$?
    else
        chsh -s "$login_shell_zsh" </dev/tty && login_shell_status=0 || login_shell_status=$?
    fi
    if [ "$login_shell_status" -ne 0 ]; then
        plasticine_login_shell_error 'chsh failed; existing tools and configuration retained. Retry with --login-shell in a native terminal; inspect account policy and /etc/shells manually.'
        return 1
    fi
    plasticine_login_shell_account || return 1
    plasticine_login_shell_current || {
        plasticine_login_shell_error 'chsh did not update the account login shell; configuration retained. Inspect native account policy and retry.'
        return 1
    }
}
