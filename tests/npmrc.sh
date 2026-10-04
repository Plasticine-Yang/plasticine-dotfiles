#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-npmrc-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'npmrc tests: %s\n' "$1" >&2; exit 1; }
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
write_config() {
    printf '%s\n' '[diff]' 'exclude = ["scripts"]' '[data]' "tools = [$1]" \
        'githubSSHKeyPath = ""' 'githubSSHKeyFingerprint = ""' \
        'githubSSHReplaceFingerprint = ""' 'githubSSHTest = false' > "$2"
}
chezmoi_run() {
    scenario=$1; shift
    HOME=$scenario/home "$chezmoi_bin" -S "$repo_dir" -D "$scenario/home" \
        -c "$scenario/config.toml" --persistent-state "$scenario/state" "$@"
}
apply() { chezmoi_run "$1" apply --no-tty; }
# shellcheck disable=SC1091
. "$repo_dir/lib/npmrc-configuration.sh"

missing=$test_root/missing
mkdir -p "$missing/home"
write_config '"npmrc"' "$missing/config.toml"
chezmoi_run "$missing" diff --no-pager > "$missing/diff"
chezmoi_run "$missing" apply --dry-run --no-tty
test ! -e "$missing/home/.npmrc" || fail 'dry-run changed target'
test ! -e "$missing/home/.plasticine" || fail 'dry-run created backups'
apply "$missing"
printf '%s\n' 'dangerously-allow-all-scripts=true' > "$missing/expected"
cmp -s "$missing/expected" "$missing/home/.npmrc" || fail 'fresh target includes extra preferences'
test "$(file_mode "$missing/home/.npmrc")" = 600 || fail 'new target is not private'
test ! -e "$missing/home/.plasticine" || fail 'fresh target created backups'

changed=$test_root/changed
mkdir -p "$changed/home"
write_config '"npmrc"' "$changed/config.toml"
cat > "$changed/home/.npmrc" <<'EOF'
# Owner preferences
registry=https://registry.npmjs.org/
//registry.npmjs.org/:_authToken=npmrc-private-marker
ignore-scripts=true
  dangerously-allow-all-scripts = false
; keep this comment
dangerously-allow-all-scripts[]=false
"dangerously-allow-all-scripts"=false
'dangerously-allow-all-scripts'=false
@company:registry=https://registry.example.com/
EOF
cp "$changed/home/.npmrc" "$changed/original"
chmod 640 "$changed/home/.npmrc"
plasticine_npmrc_preview "$changed/home" > "$changed/preview"
chezmoi_run "$changed" diff --no-pager >> "$changed/preview"
if grep -Fq npmrc-private-marker "$changed/preview"; then fail 'Preview leaked a credential'; fi
cmp -s "$changed/original" "$changed/home/.npmrc" || fail 'Preview changed target'
test ! -e "$changed/home/.plasticine" || fail 'Preview created backups'
apply "$changed"
sed '/dangerously-allow-all-scripts/d' "$changed/original" > "$changed/unrelated-before"
sed '/dangerously-allow-all-scripts/d' "$changed/home/.npmrc" > "$changed/unrelated-after"
cmp -s "$changed/unrelated-before" "$changed/unrelated-after" || fail 'unrelated settings changed'
test "$(grep -c '^dangerously-allow-all-scripts=true$' "$changed/home/.npmrc")" = 1 || fail 'duplicate/conflicting keys survived'
test "$(file_mode "$changed/home/.npmrc")" = 640 || fail 'Owner mode changed'
backup=$(find "$changed/home/.plasticine/backups/npmrc" -name '.npmrc.plasticine-backup-*')
cmp -s "$changed/original" "$backup" || fail 'backup is not the original'
test "$(file_mode "$backup")" = 600 || fail 'backup is not private'
test "$(file_mode "$changed/home/.plasticine/backups/npmrc")" = 700 || fail 'backup directory is not private'
inode=$(stat -c '%i' "$changed/home/.npmrc" 2>/dev/null || stat -f '%i' "$changed/home/.npmrc")
apply "$changed"
test "$inode" = "$(stat -c '%i' "$changed/home/.npmrc" 2>/dev/null || stat -f '%i' "$changed/home/.npmrc")" || fail 'converged rerun rewrote target'
test "$(find "$changed/home/.plasticine/backups/npmrc" -name '.npmrc.plasticine-backup-*' | wc -l | tr -d ' ')" = 1 || fail 'converged rerun added backup'

# Preserve CRLF, comments and an unrelated final line without a newline.
bytes=$test_root/bytes
mkdir -p "$bytes/home"
write_config '"npmrc"' "$bytes/config.toml"
printf 'registry=https://registry.example.com/\r\ndangerously-allow-all-scripts=false\r\n# final comment' > "$bytes/home/.npmrc"
printf 'registry=https://registry.example.com/\r\ndangerously-allow-all-scripts=true\r\n# final comment' > "$bytes/expected"
apply "$bytes"
cmp -s "$bytes/expected" "$bytes/home/.npmrc" || fail 'unrelated byte formatting changed'
append=$test_root/append
mkdir -p "$append/home"
write_config '"npmrc"' "$append/config.toml"
printf '# no trailing newline' > "$append/home/.npmrc"
printf '# no trailing newline\ndangerously-allow-all-scripts=true\n' > "$append/expected"
apply "$append"
cmp -s "$append/expected" "$append/home/.npmrc" || fail 'appended key joined an existing line'
section=$test_root/section
mkdir -p "$section/home"
write_config '"npmrc"' "$section/config.toml"
printf '%s\n' '# section preferences' '[owner]' 'dangerously-allow-all-scripts=false' > "$section/home/.npmrc"
printf '%s\n' '# section preferences' 'dangerously-allow-all-scripts=true' '[owner]' 'dangerously-allow-all-scripts=false' > "$section/expected"
apply "$section"
cmp -s "$section/expected" "$section/home/.npmrc" || fail 'preference was nested or Owner section changed'
apply "$section"
cmp -s "$section/expected" "$section/home/.npmrc" || fail 'section rerun did not converge'

unselected=$test_root/unselected
mkdir -p "$unselected/home"
write_config '' "$unselected/config.toml"
ln -s elsewhere "$unselected/home/.npmrc"
apply "$unselected"
test -L "$unselected/home/.npmrc" || fail 'unselected target changed'
test ! -e "$unselected/home/.plasticine" || fail 'unselected feature created state'
unsafe=$test_root/unsafe
mkdir -p "$unsafe/home"
write_config '"git-config","npmrc"' "$unsafe/config.toml"
ln -s elsewhere "$unsafe/home/.npmrc"
if apply "$unsafe" >/dev/null 2> "$unsafe/error"; then fail 'selected symlink accepted'; fi
test ! -e "$unsafe/home/.gitconfig" || fail 'unsafe target did not stop other configuration'
test ! -e "$unsafe/home/.plasticine" || fail 'unsafe target created backups'
invalid=$test_root/invalid
mkdir -p "$invalid/home/.plasticine"
write_config '"npmrc"' "$invalid/config.toml"
printf '%s\n' owner > "$invalid/home/.npmrc"
printf '%s\n' blocker > "$invalid/home/.plasticine/backups"
cp "$invalid/home/.npmrc" "$invalid/before"
if apply "$invalid" >/dev/null 2> "$invalid/error"; then fail 'invalid backup parent accepted'; fi
cmp -s "$invalid/before" "$invalid/home/.npmrc" || fail 'invalid parent failure changed target'
prepare_fail=$test_root/prepare-fail
mkdir -p "$prepare_fail/home" "$prepare_fail/bin"
write_config '"lazygit","npmrc"' "$prepare_fail/config.toml"
printf '%s\n' owner > "$prepare_fail/home/.npmrc"
cp "$prepare_fail/home/.npmrc" "$prepare_fail/before"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$prepare_fail/bin/lazygit"
chmod +x "$prepare_fail/bin/lazygit"
if (PATH=$prepare_fail/bin:/usr/bin:/bin apply "$prepare_fail") >/dev/null 2> "$prepare_fail/error"; then fail 'unhealthy selected tool accepted'; fi
cmp -s "$prepare_fail/before" "$prepare_fail/home/.npmrc" || fail 'tool failure changed npmrc'
test ! -e "$prepare_fail/home/.plasticine" || fail 'tool failure created backups'

# Real npm installs a local tarball offline; its postinstall writes a marker.
# The ambient Owner npmrc, environment, prefix and cache are all isolated.
npm_bin=$(command -v npm || true)
runtime=$test_root/runtime
mkdir -p "$runtime/home" "$runtime/package"
write_config '"npmrc"' "$runtime/config.toml"
probe=false
if [ -n "$npm_bin" ] && env -i HOME="$runtime/home" PATH="$PATH" "$npm_bin" \
    --userconfig "$runtime/home/.npmrc" --globalconfig /dev/null \
    config get dangerously-allow-all-scripts > "$runtime/probe.out" 2> "$runtime/probe.err"; then
    if [ "$(cat "$runtime/probe.out")" = false ]; then probe=true; fi
fi
if [ "$probe" = true ]; then
    printf '%s\n' '{"name":"plasticine-npmrc-fixture","version":"1.0.0","scripts":{"postinstall":"node postinstall.js"}}' > "$runtime/package/package.json"
    printf '%s\n' 'require("node:fs").writeFileSync(process.env.PLASTICINE_NPMRC_TEST_MARKER, "ran");' > "$runtime/package/postinstall.js"
    tar -czf "$runtime/fixture.tgz" -C "$runtime" package
    npm_install() {
        prefix=$1; shift
        env -i HOME="$runtime/home" PATH="$PATH" \
            PLASTICINE_NPMRC_TEST_MARKER="$runtime/marker" \
            "$npm_bin" --userconfig "$runtime/home/.npmrc" --globalconfig /dev/null \
            --cache "$runtime/cache" --prefix "$runtime/$prefix" --offline --no-audit --no-fund \
            install -g "$runtime/fixture.tgz" "$@" > "$runtime/$prefix.log" 2>&1
    }
    npm_install blocked
    test ! -e "$runtime/marker" || fail 'baseline policy did not block the script'
    apply "$runtime"
    npm_install allowed
    test "$(cat "$runtime/marker")" = ran || fail 'managed preference did not run postinstall'
    rm "$runtime/marker"
    npm_install ignored --ignore-scripts=true
    test ! -e "$runtime/marker" || fail 'explicit ignore-scripts was overridden'
    printf '%s\n' 'npmrc runtime: real npm blocked, allowed and explicitly ignored postinstall as expected'
elif [ "${PLASTICINE_REQUIRE_NPMRC_RUNTIME:-0}" = 1 ]; then
    printf 'npmrc runtime: npm executable = %s\n' "$npm_bin" >&2
    if [ -f "$runtime/probe.out" ]; then cat "$runtime/probe.out" "$runtime/probe.err" >&2; fi
    fail 'script-policy npm runtime required but unavailable'
else
    printf '%s\n' 'npmrc runtime: skipped (script-policy npm unavailable)' >&2
fi
printf '%s\n' 'npmrc tests passed'
