#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
zsh_bin=$(command -v zsh 2>/dev/null || true)
[ -n "$zsh_bin" ] || { printf '%s\n' 'zsh is required for fnm runtime tests.' >&2; exit 1; }
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-fnm-runtime.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'fnm runtime: %s\n' "$1" >&2; exit 1; }

run_case() {
    mode=$1
    home=$test_root/$mode
    mkdir -p "$home/.plasticine/zsh" "$home/.local/bin" "$home/.antidote" \
        "$home/.cache/antidote/github.com/romkatv/powerlevel10k"
    cp "$repo_dir/dot_plasticine/zsh/shared.zsh" "$home/.plasticine/zsh/shared.zsh"
    printf '%s\n' ':' > "$home/.p10k.zsh"
    printf '%s\n' ':' > "$home/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme"
    cat > "$home/.antidote/antidote.zsh" <<'EOF'
antidote() { case $1 in --version) return 0 ;; path) print -r -- "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k" ;; load) return 0 ;; *) return 1 ;; esac }
EOF
    cat > "$home/.local/bin/fnm" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$FNM_RUNTIME_CALLS"
if [ "$FNM_RUNTIME_MODE" = fail ]; then printf '%s\n' 'typeset -g FNM_BAD_OUTPUT_WAS_EVALUATED=1'; exit 1; fi
printf '%s\n' 'typeset -g FNM_RUNTIME_ACTIVATED=1'
EOF
    chmod +x "$home/.local/bin/fnm"
    cat > "$home/.zshrc" <<'EOF'
. "$HOME/.plasticine/zsh/shared.zsh"
typeset -g OWNER_CODE_CONTINUED=1
EOF
    : > "$home/calls"
    # The real Zsh, rather than this POSIX shell, expands fixture variables.
    # shellcheck disable=SC2016
    HOME=$home PATH=/usr/bin:/bin FNM_RUNTIME_MODE=$mode FNM_RUNTIME_CALLS=$home/calls \
        "$zsh_bin" -d -i -c 'print -r -- "active=${FNM_RUNTIME_ACTIVATED:-0} bad=${FNM_BAD_OUTPUT_WAS_EVALUATED:-0} owner=${OWNER_CODE_CONTINUED:-0}"' \
        > "$home/output" 2> "$home/stderr"
    [ "$(wc -l < "$home/calls" | tr -d ' ')" -eq 1 ] || fail "$mode initialized fnm more than once"
    grep -Fxq 'env --shell zsh' "$home/calls" || fail "$mode used the wrong activation arguments"
    grep -q 'owner=1' "$home/output" || fail "$mode stopped later Owner code"
}

run_case ok
grep -q 'active=1 bad=0 owner=1' "$test_root/ok/output" || fail 'successful output was not activated'
run_case fail
grep -q 'active=0 bad=0 owner=1' "$test_root/fail/output" || fail 'failed output was evaluated'
grep -q 'fnm activation unavailable; continuing shell startup' "$test_root/fail/stderr" || fail 'failed activation was not diagnosed'
printf '%s\n' 'fnm real-zsh runtime tests passed'
