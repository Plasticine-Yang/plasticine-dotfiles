#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
zsh_bin=$(command -v zsh)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-rust-runtime.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'rust runtime: %s\n' "$1" >&2; exit 1; }

new_case() {
    home=$test_root/$1
    mkdir -p "$home/.plasticine/zsh" "$home/.antidote"
    cp "$repo_dir/dot_plasticine/zsh/shared.zsh" "$home/.plasticine/zsh/shared.zsh"
    printf '%s\n' ':' > "$home/.p10k.zsh"
    cat > "$home/.antidote/antidote.zsh" <<'ANTIDOTE'
antidote() { return 0; }
ANTIDOTE
    cat > "$home/.zshrc" <<'ZSHRC'
. "$HOME/.plasticine/zsh/shared.zsh"
. "$HOME/.plasticine/zsh/shared.zsh"
typeset -g OWNER_CODE_CONTINUED=1
ZSHRC
}
probe() {
    # Zsh owns expansion in the runtime probe.
    # shellcheck disable=SC2016
    HOME=$home PATH=/usr/bin:/bin "$zsh_bin" -d -i -c '
        print -r -- "owner=$OWNER_CODE_CONTINUED"
        print -r -- "cargo=${commands[cargo]:-missing}"
        print -r -- "rust-home=${RUSTUP_HOME:-unset}"
        print -r -- "cargo-home=${CARGO_HOME:-unset}"
        for entry in "${path[@]}"; do print -r -- "path=$entry"; done
    ' > "$home/output" 2> "$home/stderr"
    grep -Fxq owner=1 "$home/output" || fail 'Rust PATH stopped later Owner code'
    if grep -i rust "$home/stderr"; then fail 'shell startup warned about Rust'; fi
}
seed_cargo() {
    mkdir -p "$1/bin"
    printf '%s\n' '#!/bin/sh' 'exit 99' > "$1/bin/cargo"
    printf '%s\n' '#!/bin/sh' 'exit 99' > "$1/bin/rustup"
    chmod 755 "$1/bin/cargo" "$1/bin/rustup"
    printf '%s\n' 'return 99' > "$1/env"
}

unset CARGO_HOME RUSTUP_HOME
new_case absent
probe
grep -Fxq cargo=missing "$home/output"
if grep -Fq "$home/.cargo/bin" "$home/output"; then fail 'missing Cargo home entered PATH'; fi
test ! -e "$home/.cargo" || fail 'shell created Cargo state'

new_case native
seed_cargo "$home/.cargo"
probe
grep -Fxq "cargo=$home/.cargo/bin/cargo" "$home/output"
[ "$(grep -Fxc "path=$home/.cargo/bin" "$home/output")" -eq 1 ] || fail 'Cargo PATH was duplicated'
grep -Fxq cargo-home=unset "$home/output" || fail 'shell forced CARGO_HOME'

new_case custom
custom_home=$home/custom\ cargo
seed_cargo "$custom_home"
seed_cargo "$home/.cargo"
CARGO_HOME=$custom_home RUSTUP_HOME=$home/custom-rustup probe
grep -Fxq "cargo=$custom_home/bin/cargo" "$home/output"
grep -Fxq "cargo-home=$custom_home" "$home/output"
grep -Fxq "rust-home=$home/custom-rustup" "$home/output"
[ "$(grep -Fxc "path=$custom_home/bin" "$home/output")" -eq 1 ] || fail 'custom Cargo PATH was duplicated'
if grep -Fxq "path=$home/.cargo/bin" "$home/output"; then fail 'custom Cargo home fell back to default'; fi

new_case custom-absent
seed_cargo "$home/.cargo"
CARGO_HOME=$home/missing probe
grep -Fxq cargo=missing "$home/output" || fail 'absent custom home fell back to default'
test ! -e "$home/missing" || fail 'shell created custom Cargo home'

new_case relative
mkdir -p "$home/relative/bin"
CARGO_HOME=relative probe
grep -Fxq cargo=missing "$home/output"
if grep -Fxq path=relative/bin "$home/output"; then fail 'relative Cargo bin entered PATH'; fi

# An Owner PATH that already includes Cargo stays in the same order.
new_case existing-path
seed_cargo "$home/.cargo"
# shellcheck disable=SC2016
HOME=$home PATH=/usr/bin:"$home/.cargo/bin":/bin "$zsh_bin" -d -i -c \
    'print -r -- "${(j.:.)path}"' > "$home/output" 2> "$home/stderr"
grep -Fxq "$home/.local/bin:/usr/bin:$home/.cargo/bin:/bin" "$home/output" || fail 'existing Cargo PATH order changed'
printf '%s\n' 'Rust real-Zsh runtime tests passed'
