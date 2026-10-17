# Interactive defaults; later Owner code in ~/.zshrc can override them.
# Runtime only: Antidote owns its native cache, bundles, and plugin checkouts.
# Also support an Owner explicitly sourcing this fragment without .zshenv.
if [[ ${_plasticine_environment_loaded:-0} != 1 ]]; then
    if [[ -r $HOME/.plasticine/zsh/environment.zsh ]]; then
        source "$HOME/.plasticine/zsh/environment.zsh"
    elif (( ${path[(Ie)$HOME/.local/bin]} == 0 )); then
        path+=("$HOME/.local/bin")
    fi
fi
export PATH
[[ -o interactive ]] || return 0

_plasticine_shell_warn() {
    if [[ -o interactive ]]; then
        print -ru2 -- "plasticine: $1 unavailable; continuing shell startup"
    fi
    return 0
}

# Preserve the accepted vi-mode preferences without relocating any tool state.
ZVM_VI_INSERT_ESCAPE_BINDKEY=jk
ZVM_VI_EDITOR=nvim

_plasticine_antidote=''
_plasticine_brew=''
case $(uname -s 2>/dev/null) in
    Linux) _plasticine_antidote=$HOME/.antidote/antidote.zsh ;;
    Darwin)
        _plasticine_brew=$(command -v brew 2>/dev/null)
        # The official bootstrap cannot update the parent process's PATH. Use
        # the native prefix in a new login shell without a Plasticine shim.
        if [[ -z $_plasticine_brew ]]; then
            case $(uname -m 2>/dev/null) in
                arm64|aarch64) _plasticine_brew=/opt/homebrew/bin/brew ;;
                x86_64) _plasticine_brew=/usr/local/bin/brew ;;
            esac
        fi
        if [[ -x $_plasticine_brew ]]; then
            if _plasticine_prefix=$(HOMEBREW_NO_ANALYTICS=1 "$_plasticine_brew" --prefix antidote 2>/dev/null); then
                case $_plasticine_prefix in
                    /*) _plasticine_antidote=$_plasticine_prefix/share/antidote/antidote.zsh ;;
                esac
            fi
        fi
        ;;
esac

if [[ -f $_plasticine_antidote && -r $_plasticine_antidote ]] &&
    source "$_plasticine_antidote" 2>/dev/null && (( $+functions[antidote] )); then
    # Native `load` generates and sources .zsh_plugins.zsh (and the independent
    # .zsh_plugins.local.zsh). No combined managed file, custom cache, or update.
    # Separate lists ensure a removed Owner list cannot keep loading stale plugins.
    if [[ -f $HOME/.zsh_plugins.txt && -r $HOME/.zsh_plugins.txt ]]; then
        if ! antidote load "$HOME/.zsh_plugins.txt" 2>/dev/null; then
            _plasticine_shell_warn 'managed plugins'
        fi
    else
        _plasticine_shell_warn 'managed plugin declaration'
    fi
    if [[ -e $HOME/.zsh_plugins.local.txt || -L $HOME/.zsh_plugins.local.txt ]]; then
        if [[ -f $HOME/.zsh_plugins.local.txt && -r $HOME/.zsh_plugins.local.txt ]]; then
            if ! antidote load "$HOME/.zsh_plugins.local.txt" 2>/dev/null; then
                _plasticine_shell_warn 'Owner plugins'
            fi
        else
            _plasticine_shell_warn 'Owner plugin declaration'
        fi
    fi
else
    _plasticine_shell_warn Antidote
fi

# zsh-completions contributes fpath; initialize completion using Zsh's native
# dump location. Ignore insecure completion directories rather than prompting.
if (( ! $+functions[compdef] )); then
    autoload -Uz compinit
    if ! compinit -i 2>/dev/null; then
        _plasticine_shell_warn completions
    fi
fi

if [[ -f $HOME/.p10k.zsh && -r $HOME/.p10k.zsh ]]; then
    if ! source "$HOME/.p10k.zsh" 2>/dev/null; then
        _plasticine_shell_warn 'Powerlevel10k preferences'
    fi
else
    _plasticine_shell_warn 'Powerlevel10k preferences'
fi

# Always present, independent of Feature Selection. Do not evaluate partial
# output from a failing fnm command and do not enable directory-change switching.
# A fresh Homebrew bootstrap cannot export PATH into its parent. Expose its
# native executable directory only when needed, without moving fnm or its state.
if ! command -v fnm >/dev/null 2>&1 && [[ -x $_plasticine_brew ]]; then
    if _plasticine_prefix=$(HOMEBREW_NO_ANALYTICS=1 "$_plasticine_brew" --prefix 2>/dev/null); then
        if [[ $_plasticine_prefix == /* && -x $_plasticine_prefix/bin/fnm ]]; then
            path=("$_plasticine_prefix/bin" "${path[@]}")
            export PATH
        fi
    fi
fi
# An installed fnm owns the interactive Node choice so that native `fnm use` has
# a session to retarget; an external Node on PATH must not suppress activation.
# Later Owner code in ~/.zshrc can still override the resulting PATH. For an
# inherited fnm session, create a new independent session and restore its version
# through native `fnm use`; child shells must not share the parent's mutable link.
_plasticine_fnm_node=${commands[node]:-}
_plasticine_fnm_inherited_path=${FNM_MULTISHELL_PATH:-}
_plasticine_fnm_version=''
if [[ -n $_plasticine_fnm_inherited_path &&
      $_plasticine_fnm_node == $_plasticine_fnm_inherited_path/bin/node ]]; then
    _plasticine_fnm_version=$("$_plasticine_fnm_node" --version 2>/dev/null)
fi
if command -v fnm >/dev/null 2>&1; then
    _plasticine_fnm_inherited_path_env=$PATH
    if _plasticine_fnm_env=$(fnm env --shell zsh 2>/dev/null); then
        if ! eval "$_plasticine_fnm_env" 2>/dev/null; then
            PATH=$_plasticine_fnm_inherited_path_env
            export PATH FNM_MULTISHELL_PATH=$_plasticine_fnm_inherited_path
            _plasticine_shell_warn 'fnm activation'
        elif [[ -n $_plasticine_fnm_version ]] &&
             ! fnm use --silent-if-unchanged "$_plasticine_fnm_version" >/dev/null 2>&1; then
            PATH=$_plasticine_fnm_inherited_path_env
            export PATH FNM_MULTISHELL_PATH=$_plasticine_fnm_inherited_path
            _plasticine_shell_warn 'fnm inherited version'
        fi
    else
        _plasticine_shell_warn 'fnm activation'
    fi
fi
unset _plasticine_antidote _plasticine_brew _plasticine_prefix _plasticine_fnm_env \
    _plasticine_fnm_node _plasticine_fnm_inherited_path _plasticine_fnm_version \
    _plasticine_fnm_inherited_path_env _plasticine_startup_node_bin _plasticine_fnm_default_bin
unfunction _plasticine_shell_warn
