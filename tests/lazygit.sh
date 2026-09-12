#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-lazygit-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'lazygit tests: %s\n' "$1" >&2; exit 1; }
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

work_repo=$test_root/work
mkdir -p "$work_repo"
find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$work_repo/" \;
git -C "$work_repo" init -q
git -C "$work_repo" add -A
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm lazygit-test
origin_repo=$test_root/origin.git
git clone -q --bare "$work_repo" "$origin_repo"

protect_bin=$test_root/protect-bin
mkdir -p "$protect_bin"
for command_name in zsh brew apt-get sudo chsh dscl getent; do
    cat > "$protect_bin/$command_name" <<EOF
#!/bin/sh
printf '%s\n' '$command_name probed' >> '$test_root/shell-probes'
exit 99
EOF
done
chmod +x "$protect_bin"/*

healthy_bin=$test_root/healthy-bin
mkdir -p "$healthy_bin"
cat > "$healthy_bin/lazygit" <<'EOF'
#!/bin/sh
[ -z "${PLASTICINE_TEST_LAZYGIT_UNHEALTHY:-}" ] || exit 9
[ "${1:-}" = --version ] || exit 99
printf '%s\n' healthy >> "$PLASTICINE_TEST_LAZYGIT_PROBES"
printf '%s\n' 'lazygit version 99.0.0'
EOF
chmod +x "$healthy_bin/lazygit"
base_path=$PATH

run_installer() {
    scenario=$1
    shift
    PATH=$healthy_bin:$protect_bin:$base_path \
    PLASTICINE_TEST_LAZYGIT_PROBES=$test_root/lazygit-probes \
    PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$scenario/config/state.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home \
        "$repo_dir/install.sh" "$@"
}

shell_block=$test_root/shell-block
cat > "$shell_block" <<'EOF'
# >>> Plasticine shell >>>
if [ -r "$HOME/.plasticine/zsh/shared.zsh" ]; then
    if ! . "$HOME/.plasticine/zsh/shared.zsh"; then
        if [[ -o interactive ]]; then
            print -ru2 -- "plasticine: shared shell configuration unavailable"
        fi
    fi
fi
# <<< Plasticine shell <<<
EOF
lazygit_block=$test_root/lazygit-block
cat > "$lazygit_block" <<'EOF'
# >>> Plasticine lazygit >>>
alias lg='lazygit'
# <<< Plasticine lazygit <<<
EOF

# Tool options require -y and a missing/unhealthy selected executable is never replaced.
missing_y=$test_root/missing-y; mkdir -p "$missing_y/home"
if run_installer "$missing_y" --lazygit </dev/null >/dev/null 2>&1; then fail '--lazygit without -y succeeded'; fi
test ! -e "$missing_y/data"
missing=$test_root/missing; mkdir -p "$missing/home" "$missing/empty-bin"
if PATH=$missing/empty-bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$missing/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$missing/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$missing/config/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$missing/home "$repo_dir/install.sh" -y --lazygit >"$missing/out" 2>"$missing/err"; then
    fail 'missing Lazygit succeeded'
fi
grep -Fq 'executable not found' "$missing/err"
test ! -e "$missing/home/.zshrc"
unhealthy=$test_root/unhealthy; mkdir -p "$unhealthy/home"
if PLASTICINE_TEST_LAZYGIT_UNHEALTHY=1 run_installer "$unhealthy" -y --lazygit >/dev/null 2>"$unhealthy/err"; then fail 'unhealthy Lazygit succeeded'; fi
unset PLASTICINE_TEST_LAZYGIT_UNHEALTHY
grep -Fq 'left untouched' "$unhealthy/err"
test ! -e "$unhealthy/home/.zshrc"

# Lazygit-only preserves arbitrary bytes, never probes shell state, and restores mode.
single=$test_root/single; mkdir -p "$single/home"
printf 'owner\015\012\303\251\000\377tail' > "$single/home/.zshrc"
cp "$single/home/.zshrc" "$single/before"; chmod 640 "$single/home/.zshrc"
run_installer "$single" -y --lazygit >/dev/null
cat "$lazygit_block" > "$single/expected"; cat "$single/before" >> "$single/expected"
cmp -s "$single/expected" "$single/home/.zshrc" || fail 'outside bytes changed'
test "$(file_mode "$single/home/.zshrc")" = 640 || fail 'mode not restored'
test ! -e "$test_root/shell-probes" || fail 'lazygit-only probed shell state'
backup=$(find "$single/home/.plasticine/backups/integration-blocks" -name '.zshrc.plasticine-backup-*')
cmp -s "$single/before" "$backup" || fail 'backup differs from original'
test "$(file_mode "$backup")" = 600 || fail 'backup mode is not 0600'
test "$(file_mode "$single/home/.plasticine/backups")" = 700 || fail 'backup parent mode is not 0700'
before_hash=$(find "$single/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
run_installer "$single" -y --lazygit >/dev/null
after_hash=$(find "$single/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
test "$before_hash" = "$after_hash" || fail 'satisfied rerun changed files'
test "$(find "$single/home/.plasticine/backups/integration-blocks" -name '.zshrc.plasticine-backup-*' | wc -l | tr -d ' ')" = 1 || fail 'rerun created backup'

# Existing blocks stay in place; missing selected blocks prepend in catalog order.
compose=$test_root/compose; mkdir -p "$compose/home"
printf 'prefix\n' > "$compose/home/.zshrc"; cat "$lazygit_block" >> "$compose/home/.zshrc"; printf 'suffix' >> "$compose/home/.zshrc"
run_installer "$compose" -y --lazygit >/dev/null
printf 'prefix\n' > "$compose/expected"; cat "$lazygit_block" >> "$compose/expected"; printf 'suffix' >> "$compose/expected"
cmp -s "$compose/expected" "$compose/home/.zshrc" || fail 'existing block moved'

# Selected malformed markers fail before the Lazygit health probe; malformed unselected markers are opaque.
malformed=$test_root/malformed; mkdir -p "$malformed/home"
printf '# >>> Plasticine lazygit >>\n' > "$malformed/home/.zshrc"; cp "$malformed/home/.zshrc" "$malformed/before"
rm -f "$test_root/lazygit-probes"
if run_installer "$malformed" -y --lazygit >/dev/null 2>&1; then fail 'malformed selected marker succeeded'; fi
cmp -s "$malformed/before" "$malformed/home/.zshrc" || fail 'malformed file changed'
test ! -e "$test_root/lazygit-probes" || fail 'tool probed before marker validation'
opaque=$test_root/opaque; mkdir -p "$opaque/home"
printf '# >>> Plasticine shell >>\nowner\n' > "$opaque/home/.zshrc"
run_installer "$opaque" -y --lazygit >/dev/null
grep -Fq '# >>> Plasticine shell >>' "$opaque/home/.zshrc" || fail 'unselected marker was inspected'

# Unsafe .zshrc kinds are rejected.
for kind in symlink directory fifo; do
    unsafe=$test_root/unsafe-$kind; mkdir -p "$unsafe/home"
    case $kind in symlink) ln -s "$unsafe/missing" "$unsafe/home/.zshrc" ;; directory) mkdir "$unsafe/home/.zshrc" ;; fifo) mkfifo "$unsafe/home/.zshrc" ;; esac
    if run_installer "$unsafe" -y --lazygit >/dev/null 2>&1; then fail "unsafe $kind succeeded"; fi
done

# Internal values are deduplicated/sorted and unknown values fail at init.
selection=$test_root/selection; mkdir -p "$selection/home"
PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='lazygit github-ssh lazygit shell' \
    PLASTICINE_GITHUB_SSH_KEY=/missing "$chezmoi_bin" -S "$repo_dir" -D "$selection/home" \
    --persistent-state "$selection/state" init -C "$selection/config" >/dev/null 2>&1 || true
# The missing SSH fixture stops later validation, so test the pure set without it.
PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='lazygit lazygit shell' \
    "$chezmoi_bin" -S "$repo_dir" -D "$selection/home" --persistent-state "$selection/state2" init -C "$selection/config2" >/dev/null
grep -Fq 'tools = ["lazygit","shell"]' "$selection/config2" || fail 'selection was not sorted/deduplicated'
if PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='lazygit unknown' \
    "$chezmoi_bin" -S "$repo_dir" -D "$selection/home" --persistent-state "$selection/state3" init -C "$selection/config3" >/dev/null 2>&1; then fail 'unknown selection succeeded'; fi

printf '%s\n' 'lazygit tests passed'
