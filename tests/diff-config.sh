#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-diff-config-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

work_repo=$test_root/work
mkdir -p "$work_repo"
for entry in "$repo_dir"/* "$repo_dir"/.[!.]*; do
    [ -e "$entry" ] || continue
    [ "${entry##*/}" = .git ] && continue
    cp -R "$entry" "$work_repo/"
done
mkdir -p "$work_repo/.chezmoiscripts"
cat > "$work_repo/dot_diff_config_probe" <<'EOF'
managed content from Plasticine
EOF
cat > "$work_repo/.chezmoiscripts/run_before_00_diff_config_probe.sh.tmpl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' before >> "$HOME/.diff-config-script-effects"
# DIFF_CONFIG_SCRIPT_BODY_MUST_STAY_HIDDEN
EOF
cat > "$work_repo/.chezmoiscripts/run_after_99_diff_config_probe.sh.tmpl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' after >> "$HOME/.diff-config-script-effects"
# DIFF_CONFIG_SCRIPT_BODY_MUST_STAY_HIDDEN
EOF
git -C "$work_repo" init -q
git -C "$work_repo" symbolic-ref HEAD refs/heads/main
git -C "$work_repo" add -A
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm diff-config-test
origin_repo=$test_root/origin.git
git clone -q --bare "$work_repo" "$origin_repo"

fixture_bin=$test_root/bin
mkdir -p "$fixture_bin"
cat > "$fixture_bin/lazygit" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || exit 99
printf '%s\n' 'lazygit version 0.65.1'
EOF
chmod 755 "$fixture_bin/lazygit"

run_installer() {
    scenario=$1
    shift
    HOME=$scenario/home PATH=$fixture_bin:$PATH \
    PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario/source \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$scenario/state/chezmoistate.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home \
        "$repo_dir/install.sh" "$@"
}

run_chezmoi() {
    scenario=$1
    shift
    HOME=$scenario/home "$chezmoi_bin" \
        -S "$scenario/source" \
        -D "$scenario/home" \
        -c "$scenario/config/chezmoi.toml" \
        --persistent-state "$scenario/state/chezmoistate.boltdb" \
        "$@"
}

assert_scripts_only_diff_exclude() {
    config=$1
    awk '
        /^\[diff\]$/ { in_diff = 1; sections++; next }
        /^\[/ { in_diff = 0 }
        in_diff && /^[[:space:]]*exclude = \["scripts"\][[:space:]]*$/ { excludes++ }
        END { exit !(sections == 1 && excludes == 1) }
    ' "$config" || {
        printf '%s\n' 'generated config did not contain one top-level diff.exclude with only scripts' >&2
        cat "$config" >&2
        exit 1
    }
}

# A first non-interactive initialization with an empty selection receives the
# persistent diff policy independently of any selected Feature.
empty=$test_root/empty
mkdir -p "$empty/home"
run_installer "$empty" -y > "$empty/installer-output"
assert_scripts_only_diff_exclude "$empty/config/chezmoi.toml"
grep -Fq '.diff_config_probe' "$empty/installer-output"
if grep -Fq 'DIFF_CONFIG_SCRIPT_BODY_MUST_STAY_HIDDEN' "$empty/installer-output"; then
    printf '%s\n' 'installer preview exposed a pending script body' >&2
    exit 1
fi
test "$(cat "$empty/home/.diff_config_probe")" = 'managed content from Plasticine'
test "$(sed -n '1p' "$empty/home/.diff-config-script-effects")" = before
test "$(sed -n '2p' "$empty/home/.diff-config-script-effects")" = after

# A normal diff consumes the generated config: pending non-empty scripts stay
# hidden after convergence, while a real managed-file drift remains visible.
run_chezmoi "$empty" diff --no-pager > "$empty/converged-diff"
test ! -s "$empty/converged-diff"
printf '%s\n' 'owner drift' > "$empty/home/.diff_config_probe"
run_chezmoi "$empty" diff --no-pager > "$empty/drift-diff"
grep -Fq '.diff_config_probe' "$empty/drift-diff"
grep -Fq 'managed content from Plasticine' "$empty/drift-diff"
if grep -Fq 'DIFF_CONFIG_SCRIPT_BODY_MUST_STAY_HIDDEN' "$empty/drift-diff"; then
    printf '%s\n' 'ordinary diff exposed a pending script body' >&2
    exit 1
fi
cp "$empty/source/dot_diff_config_probe" "$empty/home/.diff_config_probe"

# The diff preference does not alter apply's include set: both before and
# after scripts still execute on a later apply.
run_chezmoi "$empty" apply --no-tty >/dev/null
test "$(sed -n '3p' "$empty/home/.diff-config-script-effects")" = before
test "$(sed -n '4p' "$empty/home/.diff-config-script-effects")" = after
test "$(cat "$empty/home/.diff_config_probe")" = 'managed content from Plasticine'

# A non-shell Feature gets the same policy without losing its maintenance
# preview. This also exercises a selected-tool path distinct from empty init.
lazygit=$test_root/lazygit
mkdir -p "$lazygit/home"
run_installer "$lazygit" -y --lazygit > "$lazygit/installer-output"
assert_scripts_only_diff_exclude "$lazygit/config/chezmoi.toml"
grep -Fq 'tools = ["lazygit"]' "$lazygit/config/chezmoi.toml"
grep -Fq 'Previewing Lazygit toolchain...' "$lazygit/installer-output"
grep -Fq 'Fixed supported baseline: Lazygit 0.65.1' "$lazygit/installer-output"

# Re-initializing an existing config without the setting adopts the new
# default, and another initialization keeps one valid top-level section.
existing=$test_root/existing
mkdir -p "$existing/home" "$existing/config"
cat > "$existing/config/chezmoi.toml" <<'EOF'
[data]
    tools = []
EOF
run_installer "$existing" -y >/dev/null
assert_scripts_only_diff_exclude "$existing/config/chezmoi.toml"
run_installer "$existing" -y >/dev/null
assert_scripts_only_diff_exclude "$existing/config/chezmoi.toml"
run_chezmoi "$existing" data >/dev/null

# A representative interactive empty selection generates the same setting,
# shows the normal final confirmation, and cancellation still applies nothing.
if command -v expect >/dev/null 2>&1; then
    interactive=$test_root/interactive
    mkdir -p "$interactive/home"
    export PLASTICINE_TEST_INSTALLER="$repo_dir/install.sh"
    export PLASTICINE_TEST_CHEZMOI="$chezmoi_bin"
    export PLASTICINE_TEST_ORIGIN="$origin_repo"
    export PLASTICINE_TEST_SCENARIO="$interactive"
    export PLASTICINE_TEST_PATH="$fixture_bin:$PATH"
    expect <<'EOF'
set timeout 20
set scenario $env(PLASTICINE_TEST_SCENARIO)
set env(HOME) $scenario/home
set env(PATH) $env(PLASTICINE_TEST_PATH)
set env(PLASTICINE_CHEZMOI_BIN) $env(PLASTICINE_TEST_CHEZMOI)
set env(PLASTICINE_DOTFILES_REPO_URL) $env(PLASTICINE_TEST_ORIGIN)
set env(PLASTICINE_CHEZMOI_SOURCE_DIR) $scenario/source
set env(PLASTICINE_CHEZMOI_CONFIG_FILE) $scenario/config/chezmoi.toml
set env(PLASTICINE_CHEZMOI_STATE_FILE) $scenario/state/chezmoistate.boltdb
set env(PLASTICINE_CHEZMOI_DEST_DIR) $scenario/home
spawn $env(PLASTICINE_TEST_INSTALLER)
expect "选择要处理的工具"
send "\r"
expect "Apply these changes?"
send "n\r"
expect "Cancelled; no changes were applied."
expect eof
catch wait result
exit [lindex $result 3]
EOF
    assert_scripts_only_diff_exclude "$interactive/config/chezmoi.toml"
    test ! -e "$interactive/home/.diff_config_probe"
    test ! -e "$interactive/home/.diff-config-script-effects"
else
    printf '%s\n' 'diff config tests: expect unavailable; skipped interactive path' >&2
fi

printf '%s\n' 'diff config tests passed'
