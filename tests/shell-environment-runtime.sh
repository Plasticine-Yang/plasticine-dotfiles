#!/bin/sh
set -eu

# Start real shells from the files chezmoi produces, without sourcing .zshrc
# by hand. All executables, Node installations, and homes are disposable.
repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
zsh_bin=$(command -v zsh)
chezmoi_bin=${CHEZMOI_BIN:-chezmoi}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-environment-runtime.XXXXXX")
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
# shellcheck source=tests/lib/system-path.sh
# shellcheck disable=SC1091
. "$repo_dir/tests/lib/system-path.sh"
environment_system_path=$test_root/system-bin
plasticine_test_system_path "$environment_system_path"
fail() { printf 'shell environment runtime: %s\n' "$1" >&2; exit 1; }
home=$test_root/home
bin=$test_root/bin
mkdir -p "$home/.plasticine/zsh" "$bin" "$home/.local/share/fnm/aliases" "$home/.local/bin" \
    "$home/go/bin" "$home/.cargo/bin" "$home/.antidote"
printf '%s\n' '[data]' 'tools = ["shell"]' > "$test_root/chezmoi.toml"

for version in default selected; do
    mkdir -p "$home/nodes/$version/bin"
    cat > "$home/nodes/$version/bin/node" <<EOF
#!/bin/sh
printf '%s\\n' '$version-node'
EOF
    chmod +x "$home/nodes/$version/bin/node"
done
ln -s "$home/nodes/default" "$home/.local/share/fnm/aliases/default"
cat > "$bin/brew" <<'EOF'
#!/bin/sh
case $* in
    '--prefix antidote') printf '%s\n' "$HOME/antidote-prefix" ;;
    '--prefix') printf '%s\n' "$HOME/empty-prefix" ;;
    *) exit 99 ;;
esac
EOF
cat > "$bin/fnm" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/fnm-calls"
case $* in
    'env --shell zsh')
        mkdir -p "$HOME/multishell"
        ln -sfn "$HOME/nodes/default" "$HOME/multishell/current"
        printf 'export FNM_MULTISHELL_PATH="%s"\n' "$HOME/multishell/current"
        printf 'export PATH="%s/bin:$PATH"\n' "$HOME/multishell/current"
        ;;
    'use --silent-if-unchanged selected-node')
        ln -sfn "$HOME/nodes/selected" "$FNM_MULTISHELL_PATH"
        ;;
    *) exit 99 ;;
esac
EOF
cat > "$bin/go" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/go-calls"
exit 99
EOF
chmod +x "$bin"/*

"$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$test_root/chezmoi.toml" \
    --persistent-state "$test_root/state.boltdb" apply --include=files

run_shell() {
    mode=$1
    selected_path=$2
    inherited_fnm=${3:-}
    : > "$home/fnm-calls"
    : > "$home/go-calls"
    # These expressions are expanded by the tested Zsh, not this test runner.
    # shellcheck disable=SC2016
    /usr/bin/env -i HOME="$home" ZDOTDIR="$home" PATH="$selected_path:$bin:$environment_system_path" \
        FNM_MULTISHELL_PATH="$inherited_fnm" TERM=dumb "$zsh_bin" -d "$mode" \
        'node --version; print -r -- "local=${path[(Ie)$HOME/.local/bin]} go=${path[(Ie)$HOME/go/bin]} cargo=${path[(Ie)$HOME/.cargo/bin]}"; print -r -- "fnm-session=${FNM_MULTISHELL_PATH:-unset}"' \
        > "$test_root/out" 2> "$test_root/err" || fail "$mode could not run Node"
    [ ! -s "$home/go-calls" ] || fail 'startup executed go'
}

for mode in -c -lc -ic -lic; do
    run_shell "$mode" "$environment_system_path"
    grep -Fxq default-node "$test_root/out" || fail "$mode did not expose default Node"
    grep -Eq 'local=[1-9][0-9]* go=[1-9][0-9]* cargo=[1-9][0-9]*' "$test_root/out" ||
        fail "$mode did not expose the base tool paths"
    case $mode in
        -c|-lc)
            [ ! -s "$home/fnm-calls" ] || fail "$mode initialized interactive fnm"
            [ ! -s "$test_root/err" ] || fail "$mode printed startup diagnostics"
            ;;
    esac
    run_shell "$mode" "$home/nodes/selected/bin"
    grep -Fxq selected-node "$test_root/out" || fail "$mode replaced the selected Node"
    [ ! -s "$home/fnm-calls" ] || fail "$mode replaced an external Node with fnm"
done

ln -s "$home/nodes/selected" "$home/parent-session"
for mode in -c -lc -ic -lic; do
    run_shell "$mode" "$home/parent-session/bin" "$home/parent-session"
    grep -Fxq selected-node "$test_root/out" || fail "$mode lost the inherited fnm version"
    case $mode in
        -ic|-lic)
            grep -Fxq "fnm-session=$home/multishell/current" "$test_root/out" || fail 'child shared the parent fnm session'
            grep -Fxq 'use --silent-if-unchanged selected-node' "$home/fnm-calls" || fail 'child did not restore its inherited version'
            ;;
        *) [ ! -s "$home/fnm-calls" ] || fail 'non-interactive shell created a fnm session' ;;
    esac
    [ "$("$home/parent-session/bin/node" --version)" = selected-node ] || fail 'child changed the parent version'
done

# Repeated loading must converge, including a path with glob metacharacters.
odd_node=$home/'selected [node]'
mkdir -p "$odd_node"
cp "$home/nodes/selected/bin/node" "$odd_node/node"
# shellcheck disable=SC2016
/usr/bin/env -i HOME="$home" ZDOTDIR="$home" PATH="$odd_node:$bin:$environment_system_path" \
    "$zsh_bin" -d -c 'source "$HOME/.plasticine/zsh/environment.zsh"; source "$HOME/.plasticine/zsh/environment.zsh"; node --version; print -l -- $path' > "$test_root/out"
grep -Fxq selected-node "$test_root/out" || fail 'repeated loading replaced the selected Node'
[ "$(grep -Fxc "$odd_node" "$test_root/out")" -eq 1 ] || fail 'selected Node path was duplicated'
[ "$(grep -Fxc "$home/.local/bin" "$test_root/out")" -eq 1 ] || fail 'local bin was duplicated'

# No default installation means a quiet environment, without fnm activation.
rm "$home/.local/share/fnm/aliases/default"
: > "$home/fnm-calls"
# shellcheck disable=SC2016
/usr/bin/env -i HOME="$home" ZDOTDIR="$home" PATH="$bin:$environment_system_path" \
    "$zsh_bin" -d -c '(( ! $+commands[node] ))' > "$test_root/out" 2> "$test_root/err" || fail 'missing default unexpectedly supplied Node'
[ ! -s "$test_root/out" ] && [ ! -s "$test_root/err" ] || fail 'missing default produced output'
[ ! -s "$home/fnm-calls" ] || fail 'missing default invoked fnm'
ln -s "$home/nodes/default" "$home/.local/share/fnm/aliases/default"

# Honor explicit fnm, Go bin, and multi-root GOPATH settings without calling tools.
mkdir -p "$home/custom fnm/aliases"
ln -s "$home/nodes/selected" "$home/custom fnm/aliases/default"
printf 'export FNM_DIR="%s"\n' "$home/custom fnm" > "$home/.zshenv"
"$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$test_root/chezmoi.toml" \
    --persistent-state "$test_root/state.boltdb" apply --include=files
run_shell -c "$environment_system_path"
grep -Fxq selected-node "$test_root/out" || fail 'Owner FNM_DIR in .zshenv was ignored'
: > "$home/.zshenv"
"$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$test_root/chezmoi.toml" \
    --persistent-state "$test_root/state.boltdb" apply --include=files
# shellcheck disable=SC2016
/usr/bin/env -i HOME="$home" ZDOTDIR="$home" PATH="$bin:$environment_system_path" \
    FNM_DIR="$home/custom fnm" GOPATH="$home/go one:$home/go two" \
    "$zsh_bin" -d -c 'node --version; print -l -- $path' > "$test_root/out"
grep -Fxq selected-node "$test_root/out" || fail 'custom FNM_DIR was ignored'
grep -Fxq "$home/go one/bin" "$test_root/out" || fail 'first GOPATH root was ignored'
grep -Fxq "$home/go two/bin" "$test_root/out" || fail 'second GOPATH root was ignored'
# shellcheck disable=SC2016
/usr/bin/env -i HOME="$home" ZDOTDIR="$home" PATH="$bin:$environment_system_path" \
    GOBIN="$home/go executables" "$zsh_bin" -d -c 'print -l -- $path' > "$test_root/out"
grep -Fxq "$home/go executables" "$test_root/out" || fail 'GOBIN was ignored'
if grep -Fxq "$home/go/bin" "$test_root/out"; then fail 'GOBIN did not take precedence over GOPATH'; fi

mkdir -p "$home/custom cargo/bin"
# shellcheck disable=SC2016
/usr/bin/env -i HOME="$home" ZDOTDIR="$home" PATH="$bin:$environment_system_path" \
    CARGO_HOME="$home/custom cargo" "$zsh_bin" -d -c 'print -l -- $path' > "$test_root/out"
grep -Fxq "$home/custom cargo/bin" "$test_root/out" || fail 'non-interactive custom CARGO_HOME was ignored'
if grep -Fxq "$home/.cargo/bin" "$test_root/out"; then fail 'custom CARGO_HOME exposed the default Cargo directory'; fi

# A system login profile may put another Node ahead of the inherited one.
: > "$home/.zprofile"
"$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$test_root/chezmoi.toml" \
    --persistent-state "$test_root/state.boltdb" apply --include=files
# The Owner code follows the managed block, so emulate the system profile from
# .zshenv, before the user login profile is loaded.
# shellcheck disable=SC2016
printf 'if [[ -o login ]]; then path=("$HOME/nodes/default/bin" "${path[@]}"); fi\n' >> "$home/.zshenv"
run_shell -lc "$home/nodes/selected/bin"
grep -Fxq selected-node "$test_root/out" || fail 'login profile lost the inherited Node'

# Explicit Owner choices after the login block must survive .zshrc as well.
# shellcheck disable=SC2016
printf 'path=("$HOME/nodes/default/bin" "${path[@]}")\n' >> "$home/.zprofile"
run_shell -lic "$home/nodes/selected/bin"
grep -Fxq default-node "$test_root/out" || fail 'interactive initialization undid the Owner login choice'

printf '%s\n' 'shell environment runtime tests passed'
