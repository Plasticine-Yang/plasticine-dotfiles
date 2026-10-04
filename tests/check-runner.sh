#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-check-runner.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fixture=$test_root/repo
mkdir -p "$fixture/scripts" "$fixture/tests" "$test_root/personal-bin" "$test_root/owner-home"
cp "$repo_dir/scripts/check.sh" "$repo_dir/scripts/run-test.sh" "$fixture/scripts/"
printf '%s\n' '.agent-tmp/' > "$fixture/.gitignore"
printf '%s\n' original > "$fixture/content"
printf '%s\n' deleted > "$fixture/deleted"
cat > "$fixture/tests/cli.sh" <<'EOF'
#!/bin/sh
set -eu
mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
[ "$(cat content)" = modified ]
[ "$(cat new-file)" = untracked ]
[ "$(cat unstaged-file)" = untracked ]
[ "$(cat content-link)" = modified ]
[ ! -e deleted ]
[ ! -e .agent-tmp/owner-secret ]
[ "$(mode content)" = 644 ]
[ "$(mode scripts/check.sh)" = 755 ]
case $(umask) in 022|0022) ;; *) exit 91 ;; esac
[ -z "${PLASTICINE_TEST_POISON:-}" ]
[ ! -e "$HOME/owner-secret" ]
if command -v plasticine-test-personal-command >/dev/null 2>&1; then exit 92; fi
printf '%s\n' 'isolated dirty snapshot verified'
EOF
chmod 755 "$fixture"/scripts/*.sh "$fixture/tests/cli.sh"
git -C "$fixture" init -q
git -C "$fixture" add -A
git -C "$fixture" -c user.name=test -c user.email=test@example.com commit -qm fixture
printf '%s\n' modified > "$fixture/content"
printf '%s\n' untracked > "$fixture/new-file"
git -C "$fixture" add new-file
printf '%s\n' untracked > "$fixture/unstaged-file"
ln -s content "$fixture/content-link"
rm "$fixture/deleted"
chmod 664 "$fixture/content"
chmod 775 "$fixture/scripts/check.sh"
mkdir -p "$fixture/.agent-tmp"
printf '%s\n' secret > "$fixture/.agent-tmp/owner-secret"
printf '%s\n' secret > "$test_root/owner-home/owner-secret"
# Dependency behavior belongs to this test; production lint runs separately.
printf '%s\n' '#!/bin/sh' 'exit 0' > "$test_root/personal-bin/shellcheck"
printf '%s\n' '#!/bin/sh' 'exit 99' > "$test_root/personal-bin/plasticine-test-personal-command"
chmod 755 "$test_root/personal-bin"/*
git -C "$fixture" status --porcelain > "$test_root/before"
git -C "$fixture" diff --cached --binary > "$test_root/index-before"
(
    umask 002
    HOME=$test_root/owner-home PATH=$test_root/personal-bin:$PATH \
        PLASTICINE_TEST_POISON=owner "$fixture/scripts/check.sh" cli
) > "$test_root/output" 2>&1
grep -Fqx 'isolated dirty snapshot verified' "$test_root/output"
git -C "$fixture" status --porcelain > "$test_root/after"
cmp "$test_root/before" "$test_root/after"
git -C "$fixture" diff --cached --binary > "$test_root/index-after"
cmp "$test_root/index-before" "$test_root/index-after"
[ "$(cat "$fixture/content")" = modified ]
test -z "$(find "$fixture/.agent-tmp/checks" -mindepth 1 -print)"

set +e
PATH=$test_root/personal-bin:$PATH CHEZMOI_BIN=/missing/chezmoi \
    "$fixture/scripts/check.sh" integration > "$test_root/missing" 2>&1
status=$?
set -e
[ "$status" -eq 1 ]
grep -Fq 'missing check dependency: chezmoi (/missing/chezmoi)' "$test_root/missing"
if grep -Fq 'START test:' "$test_root/missing"; then exit 93; fi

printf '%s\n' '#!/bin/sh' 'exit 7' > "$fixture/tests/cli.sh"
set +e
PATH=$test_root/personal-bin:$PATH "$fixture/scripts/check.sh" cli > "$test_root/failure" 2>&1
status=$?
set -e
[ "$status" -eq 7 ]
grep -Fq 'FAIL test: cli (exit 7)' "$test_root/failure"
test -z "$(find "$fixture/.agent-tmp/checks" -mindepth 1 -print)"
printf '%s\n' 'local check runner tests passed'
