#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
runner=$repo_dir/scripts/run-test.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-test-runner.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

cat > "$test_root/pass.sh" <<'EOF'
#!/bin/sh
set -eu
[ "$GIT_CONFIG_KEY_0" = core.hooksPath ]
[ "$GIT_CONFIG_VALUE_0" = /dev/null ]
[ "$GIT_CONFIG_KEY_1" = trace2.eventTarget ]
[ "$GIT_CONFIG_VALUE_1" = /dev/null ]
printf '%s\n' 'fixture output'
EOF
cat > "$test_root/fail.sh" <<'EOF'
#!/bin/sh
exit 7
EOF
cat > "$test_root/hang.sh" <<'EOF'
#!/bin/sh
trap 'printf terminated > "$PLASTICINE_TEST_MARKER"; exit 0' TERM
while :; do sleep 1; done &
printf '%s\n' "$!" > "$PLASTICINE_TEST_CHILD_PID"
wait
EOF
chmod 755 "$test_root"/*.sh

pass_output=$("$runner" 5 passing-suite "$test_root/pass.sh" 2>&1)
printf '%s\n' "$pass_output" | grep -Fqx 'START test: passing-suite'
printf '%s\n' "$pass_output" | grep -Fqx 'fixture output'
printf '%s\n' "$pass_output" | grep -Eq '^PASS test: passing-suite \([0-9]+s\)$'

set +e
fail_output=$("$runner" 5 failing-suite "$test_root/fail.sh" 2>&1)
fail_status=$?
set -e
[ "$fail_status" -eq 7 ]
printf '%s\n' "$fail_output" | grep -Fqx 'FAIL test: failing-suite (exit 7)'

started_at=$(date +%s)
set +e
timeout_output=$(PLASTICINE_TEST_MARKER=$test_root/terminated \
    PLASTICINE_TEST_CHILD_PID=$test_root/child.pid \
    "$runner" 1 hanging-suite "$test_root/hang.sh" 2>&1)
timeout_status=$?
set -e
elapsed=$(( $(date +%s) - started_at ))
[ "$timeout_status" -eq 124 ]
[ "$elapsed" -lt 5 ]
[ "$(cat "$test_root/terminated")" = terminated ]
if kill -0 "$(cat "$test_root/child.pid")" 2>/dev/null; then
    printf '%s\n' 'timed-out test left a child process running' >&2
    exit 1
fi
printf '%s\n' "$timeout_output" | grep -Fqx 'TIMEOUT test: hanging-suite (1s limit)'

printf '%s\n' 'test runner tests passed'
