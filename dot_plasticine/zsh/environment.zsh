# Base environment for every Zsh. Use builtins only: no plugins, subprocesses,
# output, or fnm session creation. Owner code after the startup block can override.

# Keep the startup Node choice across macOS /etc/zprofile's path_helper reorder.
# This variable is shell-local; each child shell observes its own inherited PATH.
if [[ -z ${_plasticine_startup_node_bin:-} && -n ${commands[node]:-} ]]; then
    _plasticine_startup_node_bin=${commands[node]:h}
fi

_plasticine_environment_paths=("$HOME/.local/bin")
_plasticine_cargo_bin=${CARGO_HOME:-$HOME/.cargo}/bin
if [[ $_plasticine_cargo_bin == /* && -d $_plasticine_cargo_bin ]]; then
    _plasticine_environment_paths+=("$_plasticine_cargo_bin")
fi
if [[ -n ${GOBIN:-} ]]; then
    _plasticine_environment_paths+=("$GOBIN")
else
    # Go supports multiple workspace roots. Do not execute `go env` at startup.
    _plasticine_go_roots=(${(s.:.)${GOPATH:-$HOME/go}})
    for _plasticine_go_root in "${_plasticine_go_roots[@]}"; do
        [[ -z $_plasticine_go_root ]] || _plasticine_environment_paths+=("$_plasticine_go_root/bin")
    done
fi

# Expose native Homebrew commands to non-login shells without invoking brew.
# An inherited/custom brew on PATH already supplies its native executable dir.
if [[ $OSTYPE == darwin* && -z ${commands[brew]:-} ]]; then
    for _plasticine_brew_bin in /opt/homebrew/bin /usr/local/bin; do
        [[ ! -x $_plasticine_brew_bin/brew ]] || _plasticine_environment_paths+=("$_plasticine_brew_bin")
    done
fi
for _plasticine_environment_path in "${_plasticine_environment_paths[@]}"; do
    if (( ${path[(Ie)$_plasticine_environment_path]} == 0 )); then
        path+=("$_plasticine_environment_path")
    fi
done
if [[ -z ${_plasticine_startup_node_bin:-} && -n ${commands[node]:-} ]]; then
    _plasticine_startup_node_bin=${commands[node]:h}
fi

# Respect an explicit root and fnm's modern/legacy discovery order. Merely read
# existing directories; do not relocate state or export a guessed FNM_DIR.
if [[ -n ${FNM_DIR:-} ]]; then
    _plasticine_fnm_root=$FNM_DIR
elif [[ -d ${XDG_DATA_HOME:-$HOME/.local/share}/fnm ]]; then
    _plasticine_fnm_root=${XDG_DATA_HOME:-$HOME/.local/share}/fnm
elif [[ -d $HOME/.fnm ]]; then
    _plasticine_fnm_root=$HOME/.fnm
elif [[ $OSTYPE == darwin* && -d "$HOME/Library/Application Support/fnm" ]]; then
    _plasticine_fnm_root=$HOME/Library/Application\ Support/fnm
else
    _plasticine_fnm_root=''
fi
_plasticine_fnm_default_bin=${_plasticine_fnm_root:+$_plasticine_fnm_root/aliases/default/bin}
if [[ -z ${commands[node]:-} && -n $_plasticine_fnm_default_bin && -x $_plasticine_fnm_default_bin/node ]]; then
    _plasticine_startup_node_bin=$_plasticine_fnm_default_bin
fi
if [[ -n ${_plasticine_startup_node_bin:-} && -x $_plasticine_startup_node_bin/node ]]; then
    while (( _plasticine_node_index = ${path[(Ie)$_plasticine_startup_node_bin]} )); do
        path[_plasticine_node_index]=()
    done
    path=("$_plasticine_startup_node_bin" "${path[@]}")
fi
export PATH
_plasticine_environment_loaded=1
unset _plasticine_environment_paths _plasticine_environment_path _plasticine_go_roots \
    _plasticine_go_root _plasticine_brew_bin _plasticine_fnm_root _plasticine_node_index _plasticine_cargo_bin
