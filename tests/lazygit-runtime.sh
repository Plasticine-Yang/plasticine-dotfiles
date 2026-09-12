#!/bin/sh
set -eu

# Interface-level verification of the rendered Integration Blocks with a real
# Zsh. All state is confined to disposable homes and fixture executables.
repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi 2>/dev/null || true)}
zsh_bin=$(command -v zsh 2>/dev/null || true)
[ -n "$chezmoi_bin" ] || { printf '%s\n' 'lazygit runtime tests require chezmoi.' >&2; exit 1; }
[ -n "$zsh_bin" ] || { printf '%s\n' 'lazygit runtime tests require a real zsh.' >&2; exit 1; }

test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-lazygit-runtime.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'lazygit runtime tests: %s\n' "$1" >&2; exit 1; }

fixture_bin=$test_root/bin
mkdir -p "$fixture_bin"
cat > "$fixture_bin/lazygit" <<'EOF'
#!/bin/sh
printf 'fixture-lazygit:%s\n' "$*" >> "$PLASTICINE_LAZYGIT_RUNTIME_LOG"
EOF
cat > "$fixture_bin/owner-lazygit" <<'EOF'
#!/bin/sh
printf 'owner-lazygit:%s\n' "$*" >> "$PLASTICINE_LAZYGIT_RUNTIME_LOG"
EOF
chmod +x "$fixture_bin/lazygit" "$fixture_bin/owner-lazygit"

render_composer() {
    tools=$1
    output=$2
    config=$test_root/config-$(printf '%s' "$tools" | tr -cd '[:alnum:]-').toml
    printf '%s\n' '[data]' "tools = [$tools]" > "$config"
    "$chezmoi_bin" -S "$repo_dir" -D "$test_root/home" -c "$config" \
        execute-template < "$repo_dir/.chezmoitemplates/zshrc-integration-blocks" > "$output"
}

run_zsh() {
    runtime_home=$1
    command=$2
    HOME=$runtime_home ZDOTDIR=$runtime_home PATH=$fixture_bin:/usr/bin:/bin \
        PLASTICINE_LAZYGIT_RUNTIME_LOG=$runtime_home/runtime.log \
        "$zsh_bin" -d -i -c "$command" >"$runtime_home/stdout" 2>"$runtime_home/stderr"
}

# Lazygit-only: the repository's exact block is composed into a real .zshrc,
# the alias resolves by name through PATH, and later Owner content still runs.
lazygit_home=$test_root/lazygit-only
mkdir -p "$lazygit_home"
cat > "$lazygit_home/owner" <<'EOF'
typeset -g PLASTICINE_OWNER_RAN=1
path=("$HOME/owner-bin" $path)
EOF
render_composer '"lazygit"' "$test_root/lazygit-composer"
# shellcheck disable=SC1090,SC1091
. "$test_root/lazygit-composer"
plasticine_integration_compose "$lazygit_home/owner" "$lazygit_home/.zshrc"
cp "$lazygit_home/.zshrc" "$lazygit_home/before"
: > "$lazygit_home/runtime.log"
# The single-quoted command is intentionally expanded by the probed Zsh.
# shellcheck disable=SC2016
run_zsh "$lazygit_home" 'lg runtime argument; print -r -- "owner=$PLASTICINE_OWNER_RAN path=$path[1]"'
grep -Fxq 'fixture-lazygit:runtime argument' "$lazygit_home/runtime.log" || fail 'lg did not invoke the selected healthy lazygit command'
grep -Fxq "owner=1 path=$lazygit_home/owner-bin" "$lazygit_home/stdout" || fail 'later Owner content did not run or override PATH'
plasticine_integration_compose "$lazygit_home/.zshrc" "$lazygit_home/again"
cmp -s "$lazygit_home/before" "$lazygit_home/again" || fail 'lazygit-only composition did not converge byte-for-byte'

# Later Owner code may deliberately override the managed alias.
override_home=$test_root/owner-override
mkdir -p "$override_home"
printf "alias lg='owner-lazygit'\n" > "$override_home/owner"
plasticine_integration_compose "$override_home/owner" "$override_home/.zshrc"
: > "$override_home/runtime.log"
run_zsh "$override_home" 'lg owner argument'
grep -Fxq 'owner-lazygit:owner argument' "$override_home/runtime.log" || fail 'later Owner alias did not override the managed default'

# Combined shell+lazygit rendering uses the real blocks. An existing Lazygit
# block remains in place, the missing shell block is prepended in catalog order,
# both execute, and recomposition is byte-identical.
combined_home=$test_root/combined
mkdir -p "$combined_home/.plasticine/zsh"
cat > "$combined_home/.plasticine/zsh/shared.zsh" <<'EOF'
typeset -g PLASTICINE_SHARED_RAN=1
EOF
cat > "$combined_home/input" <<'EOF'
owner-prefix
# >>> Plasticine lazygit >>>
alias lg='stale-lazygit'
# <<< Plasticine lazygit <<<
typeset -g PLASTICINE_OWNER_RAN=1
EOF
render_composer '"shell","lazygit"' "$test_root/combined-composer"
# shellcheck disable=SC1090,SC1091
. "$test_root/combined-composer"
plasticine_integration_compose "$combined_home/input" "$combined_home/.zshrc"
first_line=$(sed -n '1p' "$combined_home/.zshrc")
[ "$first_line" = '# >>> Plasticine shell >>>' ] || fail 'missing shell block was not inserted first in catalog order'
grep -n '^owner-prefix$' "$combined_home/.zshrc" | grep -q '^10:' || fail 'existing content before the Lazygit block moved unexpectedly'
: > "$combined_home/runtime.log"
# shellcheck disable=SC2016
run_zsh "$combined_home" 'lg combined; print -r -- "shared=$PLASTICINE_SHARED_RAN owner=$PLASTICINE_OWNER_RAN"'
grep -Fxq 'fixture-lazygit:combined' "$combined_home/runtime.log" || fail 'combined lg alias did not invoke lazygit'
grep -Fxq 'shared=1 owner=1' "$combined_home/stdout" || fail 'combined shell or later Owner content did not execute'
plasticine_integration_compose "$combined_home/.zshrc" "$combined_home/again"
cmp -s "$combined_home/.zshrc" "$combined_home/again" || fail 'combined composition did not converge byte-for-byte'

"$zsh_bin" -n "$lazygit_home/.zshrc" "$override_home/.zshrc" "$combined_home/.zshrc"
printf '%s\n' 'lazygit runtime tests passed'
