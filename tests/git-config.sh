#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-git-config-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'git-config tests: %s\n' "$1" >&2; exit 1; }
file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}
write_config() {
    printf '%s\n' '[data]' "tools = [$1]" \
        'githubSSHKeyPath = ""' 'githubSSHKeyFingerprint = ""' \
        'githubSSHReplaceFingerprint = ""' 'githubSSHTest = false' > "$2"
}
chezmoi_run() {
    scenario=$1; shift
    HOME=$scenario/home GIT_CONFIG_NOSYSTEM=1 "$chezmoi_bin" \
        -S "$repo_dir" -D "$scenario/home" -c "$scenario/config.toml" \
        --persistent-state "$scenario/state" "$@"
}
apply() { scenario=$1; shift; chezmoi_run "$scenario" apply --no-tty "$@"; }

# Missing target: dry-run and Preview are effect free, then the real Git
# executable observes the shared values and the final local override.
missing=$test_root/missing; mkdir -p "$missing/home"
write_config '"git-config"' "$missing/config.toml"
printf '%s\n' '[user]' 'name = local-owner-marker-09' \
    '[plasticine]' 'marker = override-must-stay-private-09' > "$missing/home/.gitconfig.local"
cp "$missing/home/.gitconfig.local" "$missing/local-before"
chezmoi_run "$missing" diff --no-pager --exclude=scripts > "$missing/preview"
grep -Fq '.gitconfig' "$missing/preview" || fail 'Preview omitted the selected target'
grep -Fq 'path = ~/.gitconfig.local' "$missing/preview" || fail 'Preview omitted the final include'
if grep -Fq 'override-must-stay-private-09' "$missing/preview"; then
    fail 'Preview traversed the local override'
fi
apply "$missing" --dry-run
test ! -e "$missing/home/.gitconfig" || fail 'dry-run wrote .gitconfig'
test ! -e "$missing/home/.plasticine" || fail 'dry-run created backup state'
apply "$missing"
cmp -s "$missing/local-before" "$missing/home/.gitconfig.local" || fail 'local override bytes changed'
test "$(HOME=$missing/home GIT_CONFIG_NOSYSTEM=1 git config --global --includes --get user.name)" = local-owner-marker-09 || fail 'local name did not override shared name'
test "$(HOME=$missing/home GIT_CONFIG_NOSYSTEM=1 git config --global --includes --get user.email)" = 975036719@qq.com || fail 'shared email missing'
test "$(HOME=$missing/home GIT_CONFIG_NOSYSTEM=1 git config --global --includes --get init.defaultBranch)" = main || fail 'default branch missing'
test "$(HOME=$missing/home GIT_CONFIG_NOSYSTEM=1 git config --global --includes --get pull.rebase)" = true || fail 'pull.rebase missing'
test "$(tail -n 2 "$missing/home/.gitconfig" | head -n 1)" = '[include]' || fail 'local include is not the final section'
test ! -e "$missing/home/.plasticine" || fail 'fresh apply created a backup directory'

# Changed regular targets are previewed, backed up privately, and retain their
# unusual Owner mode. A converged rerun neither rewrites nor adds a backup.
changed=$test_root/changed; mkdir -p "$changed/home"
write_config '"git-config"' "$changed/config.toml"
printf '%s\n' '[user]' 'name = old-shared-owner' > "$changed/home/.gitconfig"
printf '%s\n' '[plasticine]' 'marker = changed-local-marker-09' > "$changed/home/.gitconfig.local"
chmod 640 "$changed/home/.gitconfig"
cp "$changed/home/.gitconfig" "$changed/original"
chezmoi_run "$changed" diff --no-pager --exclude=scripts > "$changed/preview"
grep -Fq 'old-shared-owner' "$changed/preview" || fail 'changed target was not previewed'
apply "$changed"
backup=$(find "$changed/home/.plasticine/backups/git-config" -name '.gitconfig.plasticine-backup-*')
test -n "$backup" || fail 'changed target was not backed up'
cmp -s "$changed/original" "$backup" || fail 'backup differs from original'
if grep -Fq 'changed-local-marker-09' "$backup"; then fail 'backup traversed the local override'; fi
test "$(file_mode "$backup")" = 600 || fail 'backup is not private'
test "$(file_mode "$changed/home/.plasticine/backups")" = 700 || fail 'backup parent is not private'
test "$(file_mode "$changed/home/.plasticine/backups/git-config")" = 700 || fail 'backup directory is not private'
test "$(file_mode "$changed/home/.gitconfig")" = 640 || fail 'Owner mode was not restored'
before_hash=$(shasum -a 256 "$changed/home/.gitconfig" | awk '{print $1}')
before_count=$(find "$changed/home/.plasticine/backups/git-config" -name '.gitconfig.plasticine-backup-*' | wc -l | tr -d ' ')
apply "$changed"
test "$before_hash" = "$(shasum -a 256 "$changed/home/.gitconfig" | awk '{print $1}')" || fail 'converged rerun rewrote content'
test "$before_count" = "$(find "$changed/home/.plasticine/backups/git-config" -name '.gitconfig.plasticine-backup-*' | wc -l | tr -d ' ')" || fail 'converged rerun added a backup'

# Unselected Git configuration is not inspected, even when both the managed
# target and the override would be invalid if selected.
unselected=$test_root/unselected; mkdir -p "$unselected/home/real"
write_config '' "$unselected/config.toml"
ln -s real/target "$unselected/home/.gitconfig"
mkdir "$unselected/home/.gitconfig.local"
apply "$unselected"
test -L "$unselected/home/.gitconfig" || fail 'unselected target changed'
test -d "$unselected/home/.gitconfig.local" || fail 'unselected override changed'
test ! -e "$unselected/home/.plasticine" || fail 'unselected feature created backup state'

# Selected unsafe targets and invalid backup parents fail before mutation.
unsafe=$test_root/unsafe; mkdir -p "$unsafe/home"; write_config '"git-config"' "$unsafe/config.toml"
ln -s elsewhere "$unsafe/home/.gitconfig"
if apply "$unsafe" >/dev/null 2>"$unsafe/error"; then fail 'symlink target was accepted'; fi
test -L "$unsafe/home/.gitconfig" || fail 'unsafe target changed'
test ! -e "$unsafe/home/.plasticine" || fail 'unsafe target created backup state'
invalid_parent=$test_root/invalid-parent; mkdir -p "$invalid_parent/home/.plasticine"
write_config '"git-config"' "$invalid_parent/config.toml"
printf '%s\n' owner > "$invalid_parent/home/.gitconfig"
printf '%s\n' blocker > "$invalid_parent/home/.plasticine/backups"
cp "$invalid_parent/home/.gitconfig" "$invalid_parent/before"
if apply "$invalid_parent" >/dev/null 2>"$invalid_parent/error"; then fail 'invalid backup parent was accepted'; fi
cmp -s "$invalid_parent/before" "$invalid_parent/home/.gitconfig" || fail 'invalid-parent failure changed target'
test "$(cat "$invalid_parent/home/.plasticine/backups")" = blocker || fail 'invalid parent changed'

# A selected tool failure happens before Git configuration backup/application.
prepare_fail=$test_root/prepare-fail; mkdir -p "$prepare_fail/home" "$prepare_fail/bin"
write_config '"git-config","lazygit"' "$prepare_fail/config.toml"
printf '%s\n' owner-before-tool-failure > "$prepare_fail/home/.gitconfig"
cp "$prepare_fail/home/.gitconfig" "$prepare_fail/before"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$prepare_fail/bin/lazygit"; chmod +x "$prepare_fail/bin/lazygit"
if PATH=$prepare_fail/bin:/usr/bin:/bin chezmoi_run "$prepare_fail" apply --no-tty >/dev/null 2>"$prepare_fail/error"; then
    fail 'unhealthy selected tool did not fail'
fi
cmp -s "$prepare_fail/before" "$prepare_fail/home/.gitconfig" || fail 'tool failure changed Git configuration'
test ! -e "$prepare_fail/home/.plasticine" || fail 'tool failure created Git configuration backup'

printf '%s\n' 'git-config tests passed'
