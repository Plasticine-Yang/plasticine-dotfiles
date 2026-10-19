#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
zsh_bin=$(command -v zsh)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-uv-runtime.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'uv runtime: %s\n' "$1" >&2; exit 1; }

new_case() {
    home=$test_root/$1
    mkdir -p "$home/.plasticine/zsh" "$home/.antidote" "$home/bin" "$home/.local/bin"
    cp "$repo_dir/dot_plasticine/zsh/shared.zsh" "$home/.plasticine/zsh/shared.zsh"
    cp "$repo_dir/dot_plasticine/zsh/environment.zsh" "$home/.plasticine/zsh/environment.zsh"
    cat > "$home/bin/brew" <<'BREW'
#!/bin/sh
printf '%s\n' "$HOME/no-host-tools"
BREW
    chmod +x "$home/bin/brew"
    printf '%s\n' ':' > "$home/.p10k.zsh"
    cat > "$home/.antidote/antidote.zsh" <<'ANTIDOTE'
antidote() { return 0; }
ANTIDOTE
    cat > "$home/.zshrc" <<'ZSHRC'
. "$HOME/.plasticine/zsh/shared.zsh"
. "$HOME/.plasticine/zsh/shared.zsh"
typeset -g OWNER_CODE_CONTINUED=1
ZSHRC
    marker=$home/uv-invoked
}
seed_uv() {
    cat > "$home/.local/bin/uv" <<UV
#!/bin/sh
printf '%s\n' invoked >> "$marker"
exit 99
UV
    cat > "$home/.local/bin/uvx" <<UVX
#!/bin/sh
printf '%s\n' invoked >> "$marker"
exit 99
UVX
    chmod 755 "$home/.local/bin/uv" "$home/.local/bin/uvx"
}
probe() {
    # Zsh owns expansion in the runtime probe.
    # shellcheck disable=SC2016
    HOME=$home PATH="$home/bin:/usr/bin:/bin" "$zsh_bin" -d -i -c '
        print -r -- "owner=$OWNER_CODE_CONTINUED"
        print -r -- "uv=${commands[uv]:-missing}"
        print -r -- "uvx=${commands[uvx]:-missing}"
        print -r -- "install-dir=${UV_INSTALL_DIR:-unset}"
        for entry in "${path[@]}"; do print -r -- "path=$entry"; done
    ' > "$home/output" 2> "$home/stderr"
    grep -Fxq owner=1 "$home/output" || fail 'uv PATH stopped later Owner code'
    [ ! -e "$marker" ] || fail 'interactive startup invoked uv'
}

new_case absent
probe
grep -Fxq uv=missing "$home/output" || fail 'absent uv was resolved'
grep -Fxq uvx=missing "$home/output" || fail 'absent uvx was resolved'
if grep -i uv "$home/stderr"; then fail 'shell startup warned about uv'; fi
test ! -e "$home/.local/share/uv" || fail 'shell created uv data'
test ! -e "$home/.config/uv" || fail 'shell created uv configuration'

new_case native
seed_uv
probe
grep -Fxq "uv=$home/.local/bin/uv" "$home/output" || fail 'managed uv is not on PATH'
grep -Fxq "uvx=$home/.local/bin/uvx" "$home/output" || fail 'managed uvx is not on PATH'
[ "$(grep -Fxc "path=$home/.local/bin" "$home/output")" -eq 1 ] || fail 'uv PATH was duplicated'
grep -Fxq install-dir=unset "$home/output" || fail 'shell forced UV_INSTALL_DIR'
[ -x "$home/.local/bin/uv" ] || fail 'shell startup replaced uv'

# An Owner PATH that already contains the executable directory keeps its order.
new_case existing-path
seed_uv
# shellcheck disable=SC2016
HOME=$home PATH="$home/bin:/usr/bin:$home/.local/bin:/bin" "$zsh_bin" -d -i -c \
    '(( ${path[(Ie)/usr/bin]} < ${path[(Ie)$HOME/.local/bin]} && ${path[(Ie)$HOME/.local/bin]} < ${path[(Ie)/bin]} ))' \
    > "$home/output" 2> "$home/stderr" || fail 'existing uv PATH order changed'
printf '%s\n' 'uv real-Zsh runtime tests passed'
