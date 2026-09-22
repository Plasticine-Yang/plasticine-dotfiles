#!/bin/sh
set -eu

# The combined scenarios exercise the default managed Neovim location. Do not
# inherit a developer/CI runner's alternate Neovim application or config root.
unset NVIM_APPNAME XDG_CONFIG_HOME

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-combined-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'combined installation: %s\n' "$1" >&2; exit 1; }

work_repo=$test_root/work
mkdir -p "$work_repo"
find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git ! -name dist -exec cp -R {} "$work_repo/" \;

# The individual Feature suites exercise their real network/package adapters.
# This fixture replaces only those adapters so this suite can observe the real
# install.sh -> chezmoi ordering and recovery contract deterministically.
for feature in fnm herdr lazygit neovim shell; do
    # These single-quoted fragments are copied verbatim into generated fixture
    # modules; expansion belongs to the generated script at runtime.
    # shellcheck disable=SC2016
    case $feature in
        shell) extra='
plasticine_shell_plan() { fixture_call shell-plan; shell_antidote_route=existing; shell_zsh=/bin/zsh; }
plasticine_shell_sync_plugins() { fixture_call shell-sync; fixture_fail shell-sync || return 1; fixture_assert_config; [ -f "$PLASTICINE_CHEZMOI_DEST_DIR/.zshrc" ] || return 93; }' ;;
        neovim) extra='
plasticine_neovim_sync() { fixture_call neovim-sync; fixture_fail neovim-sync || return 1; fixture_assert_config; }' ;;
        fnm) extra='
plasticine_fnm_plan() { fixture_call fnm-plan; fnm_os=Linux; fnm_brew_route=none; }' ;;
        herdr) extra='
plasticine_herdr_prepare() {
    fixture_call herdr-query
    fixture_fail herdr-query || return 1
    target=$(cat "$PLASTICINE_COMBINED_TARGETS/herdr")
    state=$PLASTICINE_CHEZMOI_DEST_DIR/.fixture/herdr
    current=$(cat "$state" 2>/dev/null || true)
    if [ "$current" != "$target" ]; then
        fixture_call herdr-mutate-$target
        fixture_fail herdr-mutate || return 1
        mkdir -p "${state%/*}" "$PLASTICINE_CHEZMOI_DEST_DIR/.local/bin"
        printf "%s\n" "$target" > "$state"
    else
        fixture_call herdr-current-$target
    fi
    cat > "$PLASTICINE_CHEZMOI_DEST_DIR/.local/bin/herdr" <<HERDR_FIXTURE
#!/bin/sh
case \${1:-} in
    --version) printf "%s\\n" "herdr $target" ;;
    config) [ "\${2:-}" = check ] ;;
    status) exit 1 ;;
    *) exit 90 ;;
esac
HERDR_FIXTURE
    chmod 755 "$PLASTICINE_CHEZMOI_DEST_DIR/.local/bin/herdr"
}' ;;
        *) extra='' ;;
    esac
    module=$work_repo/lib/$feature-bootstrap.sh
    sed "s/@FEATURE@/$feature/g" > "$module" <<'EOF'
#!/bin/sh
fixture_call() { printf '%s\n' "$1" >> "$PLASTICINE_COMBINED_CALLS"; }
fixture_fail() { [ "${PLASTICINE_COMBINED_FAIL:-}" != "$1" ]; }
fixture_assert_config() {
    [ -f "$PLASTICINE_CHEZMOI_DEST_DIR/.gitconfig" ] || return 91
    [ -f "$PLASTICINE_CHEZMOI_DEST_DIR/.config/nvim/init.lua" ] || return 92
}
plasticine_@FEATURE@_plan() { fixture_call @FEATURE@-plan; return 0; }
plasticine_@FEATURE@_preview() { printf 'fixture preview @FEATURE@; target resolved only during apply\n'; }
plasticine_@FEATURE@_prepare() {
    fixture_call @FEATURE@-query
    fixture_fail @FEATURE@-query || return 1
    target=$(cat "$PLASTICINE_COMBINED_TARGETS/@FEATURE@")
    state=$PLASTICINE_CHEZMOI_DEST_DIR/.fixture/@FEATURE@
    current=$(cat "$state" 2>/dev/null || true)
    if [ "$current" != "$target" ]; then
        fixture_call @FEATURE@-mutate-$target
        fixture_fail @FEATURE@-mutate || return 1
        mkdir -p "${state%/*}"
        printf '%s\n' "$target" > "$state"
    else
        fixture_call @FEATURE@-current-$target
    fi
}
EOF
    printf '%s\n' "$extra" >> "$module"
done

cat > "$work_repo/lib/login-shell-bootstrap.sh" <<'EOF'
#!/bin/sh
plasticine_login_shell_plan() { printf '%s\n' login-shell-plan >> "$PLASTICINE_COMBINED_CALLS"; }
plasticine_login_shell_preview() { printf '%s\n' 'fixture preview login-shell'; }
plasticine_login_shell_apply() {
    printf '%s\n' login-shell-apply >> "$PLASTICINE_COMBINED_CALLS"
    [ "${PLASTICINE_COMBINED_FAIL:-}" != login-shell ]
}
EOF

git -C "$work_repo" init -q
git -C "$work_repo" symbolic-ref HEAD refs/heads/main
git -C "$work_repo" add -A
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm combined-test
origin_repo=$test_root/origin.git
git clone -q --bare "$work_repo" "$origin_repo"

targets=$test_root/targets
mkdir -p "$targets"
for feature in fnm herdr lazygit neovim shell; do printf '%s\n' 1 > "$targets/$feature"; done

run_installer() {
    scenario=$1
    shift
    HOME=$scenario/home \
    PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario/source \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$scenario/config/chezmoistate.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home \
    PLASTICINE_COMBINED_CALLS=$scenario/calls \
    PLASTICINE_COMBINED_TARGETS=$targets \
    PLASTICINE_COMBINED_FAIL=${scenario_fail:-} \
        "$repo_dir/install.sh" "$@"
}

make_key() {
    mkdir -p "$1/key"
    ssh-keygen -q -t ed25519 -N '' -C combined-fixture -f "$1/key/id_ed25519"
}

# Interactive selection exposes the same eight Features. Selecting all and
# cancelling after Preview records the canonical selection but performs no
# target lookup or selected mutation.
if command -v expect >/dev/null 2>&1; then
    interactive=$test_root/interactive
    mkdir -p "$interactive/home"
    make_key "$interactive"
    export PLASTICINE_COMBINED_INSTALLER="$repo_dir/install.sh"
    export PLASTICINE_COMBINED_CHEZMOI="$chezmoi_bin"
    export PLASTICINE_COMBINED_ORIGIN="$origin_repo"
    export PLASTICINE_COMBINED_SCENARIO="$interactive"
    export PLASTICINE_COMBINED_KEY="$interactive/key/id_ed25519"
    export PLASTICINE_COMBINED_TARGETS="$targets"
    expect <<'EOF'
set timeout 30
set scenario $env(PLASTICINE_COMBINED_SCENARIO)
set env(HOME) $scenario/home
set env(PLASTICINE_CHEZMOI_BIN) $env(PLASTICINE_COMBINED_CHEZMOI)
set env(PLASTICINE_DOTFILES_REPO_URL) $env(PLASTICINE_COMBINED_ORIGIN)
set env(PLASTICINE_CHEZMOI_SOURCE_DIR) $scenario/source
set env(PLASTICINE_CHEZMOI_CONFIG_FILE) $scenario/config/chezmoi.toml
set env(PLASTICINE_CHEZMOI_STATE_FILE) $scenario/config/state
set env(PLASTICINE_CHEZMOI_DEST_DIR) $scenario/home
set env(PLASTICINE_COMBINED_CALLS) $scenario/calls
spawn $env(PLASTICINE_COMBINED_INSTALLER)
expect "选择要处理的工具"
after 300
send "\001"
after 300
send "\r"
expect "GitHub SSH 私钥路径"
after 300
send -- "$env(PLASTICINE_COMBINED_KEY)\r"
expect "配置完成后测试 GitHub SSH 连接"
after 300
send "n\r"
expect "Apply these changes?"
after 300
send "n\r"
expect eof
catch wait result
exit [lindex $result 3]
EOF
    interactive_tools=$(sed -n 's/^[[:space:]]*tools = //p' "$interactive/config/chezmoi.toml")
    for feature in fnm git-config github-ssh herdr lazygit login-shell neovim shell; do
        case $interactive_tools in *"\"$feature\""*) ;; *) fail "interactive selection omitted $feature" ;; esac
    done
    if grep -q -- '-query' "$interactive/calls"; then fail 'interactive cancellation queried current targets'; fi
    if grep -Fxq login-shell-apply "$interactive/calls"; then fail 'cancellation changed the login shell'; fi
    test ! -e "$interactive/home/.gitconfig"
    test ! -e "$interactive/home/.ssh"
    test ! -e "$interactive/home/.config"
fi

assert_order() {
    previous=0
    for event in "$@"; do
        line=$(grep -n -F -m1 "$event" "$scenario/calls" | cut -d: -f1)
        [ -n "$line" ] || fail "missing event: $event"
        [ "$line" -gt "$previous" ] || fail "event out of order: $event"
        previous=$line
    done
}

# Complete explicit selection uses a canonical set regardless of CLI order.
scenario=$test_root/all
mkdir -p "$scenario/home"
make_key "$scenario"
printf '%s\n' '# owner trailer' 'export COMBINED_OWNER=kept' > "$scenario/home/.zshrc"
printf '%s\n' '[user]' 'name = local-owner' > "$scenario/home/.gitconfig.local"
cp "$scenario/home/.gitconfig.local" "$scenario/local-before"
run_installer "$scenario" -y --neovim --github-ssh \
    --github-ssh-key "$scenario/key/id_ed25519" --herdr --git-config \
    --shell --fnm --lazygit --login-shell >/dev/null
grep -Fq 'tools = ["fnm","git-config","github-ssh","herdr","lazygit","login-shell","neovim","shell"]' \
    "$scenario/config/chezmoi.toml" || fail 'full selection was not canonicalized'
test -f "$scenario/home/.ssh/id_github"
test -f "$scenario/home/.gitconfig"
test "$(find "$scenario/home/.config/nvim" -type f | wc -l | tr -d ' ')" -eq 12
grep -Fq "alias lg='lazygit'" "$scenario/home/.zshrc"
grep -Fq 'export COMBINED_OWNER=kept' "$scenario/home/.zshrc"
cmp -s "$scenario/local-before" "$scenario/home/.gitconfig.local"
assert_order fnm-query herdr-query lazygit-query shell-query neovim-query \
    neovim-sync shell-sync login-shell-apply

# A later target generation advances all selected versioned tools, while a
# configuration-only rerun never probes them and does not touch sentinels.
: > "$scenario/calls"
for feature in fnm herdr lazygit neovim shell; do printf '%s\n' 2 > "$targets/$feature"; done
run_installer "$scenario" -y --shell --lazygit --fnm --neovim --herdr >/dev/null
if grep -Fq login-shell "$scenario/calls"; then fail 'shell implicitly selected login-shell'; fi
for feature in fnm herdr lazygit neovim shell; do
    grep -Fxq "$feature-mutate-2" "$scenario/calls" || fail "$feature did not advance"
done
printf '%s\n' untouched > "$scenario/home/.fixture/unselected"
: > "$scenario/calls"
run_installer "$scenario" -y --git-config >/dev/null
test ! -s "$scenario/calls" || fail 'configuration-only selection probed a versioned tool'
grep -Fxq untouched "$scenario/home/.fixture/unselected"

# A late preparation failure retains earlier native effects but applies no
# selected configuration; retry reuses current work and completes the rest.
scenario=$test_root/prepare-retry
mkdir -p "$scenario/home"
printf '%s\n' 3 > "$targets/fnm"
scenario_fail=herdr-query
if run_installer "$scenario" -y --git-config --fnm --herdr >"$scenario/out" 2>"$scenario/err"; then
    fail 'late target lookup failure was reported as success'
fi
test "$(cat "$scenario/home/.fixture/fnm")" = 3
test ! -e "$scenario/home/.gitconfig" || fail 'configuration applied after preparation failure'
scenario_fail=
: > "$scenario/calls"
run_installer "$scenario" -y --git-config --fnm --herdr >/dev/null
grep -Fxq fnm-current-3 "$scenario/calls" || fail 'retry reinstalled current fnm'
test -f "$scenario/home/.gitconfig"

# Failure after configuration is explicitly partial. A retry does not create
# redundant configuration backups and finishes native readiness.
scenario=$test_root/plugin-retry
mkdir -p "$scenario/home/.config/nvim"
printf '%s\n' old > "$scenario/home/.config/nvim/init.lua"
scenario_fail=neovim-sync
if run_installer "$scenario" -y --git-config --neovim >"$scenario/out" 2>"$scenario/err"; then
    fail 'plugin synchronization failure was reported as success'
fi
test -f "$scenario/home/.gitconfig"
backup_count=$(find "$scenario/home/.plasticine/backups/neovim" -type f ! -name pending-modes | wc -l | tr -d ' ')
scenario_fail=
: > "$scenario/calls"
run_installer "$scenario" -y --git-config --neovim >/dev/null
test "$(find "$scenario/home/.plasticine/backups/neovim" -type f ! -name pending-modes | wc -l | tr -d ' ')" -eq "$backup_count"
grep -Fxq neovim-sync "$scenario/calls"

# Dry-run executes the rendered public interface without target lookup. Empty
# selection likewise performs prerequisite/source maintenance only.
scenario=$test_root/dry
mkdir -p "$scenario/home" "$scenario/config"
PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='fnm herdr lazygit login-shell neovim shell' \
PLASTICINE_COMBINED_CALLS=$scenario/calls PLASTICINE_COMBINED_TARGETS=$targets \
PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home \
    "$chezmoi_bin" -S "$work_repo" -D "$scenario/home" --persistent-state "$scenario/config/state" \
    init -C "$scenario/config/chezmoi.toml" --no-tty
"$chezmoi_bin" -S "$work_repo" -D "$scenario/home" -c "$scenario/config/chezmoi.toml" \
    --persistent-state "$scenario/config/state" apply --dry-run --no-tty >/dev/null
test ! -e "$scenario/calls" || fail 'dry-run queried or mutated selected tools'
scenario=$test_root/empty
mkdir -p "$scenario/home"
run_installer "$scenario" -y >/dev/null
test ! -e "$scenario/calls" || fail 'empty selection probed a Feature'
test ! -e "$scenario/home/.gitconfig"

printf '%s\n' 'combined installation tests passed'
