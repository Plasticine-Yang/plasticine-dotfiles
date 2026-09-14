#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
gate=$repo_dir/scripts/require-ci-success.sh
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-ci-gate-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
revision=0123456789abcdef0123456789abcdef01234567

cat > "$test_root/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$PLASTICINE_TEST_GH_CALLS"
case $* in
    *'/jobs?'*)
        case $PLASTICINE_TEST_SCENARIO in
            missing-job)
                printf '%s\tsuccess\n' \
                    'Test (ubuntu-24.04)' \
                    'Test (macos-14)' \
                    'Debian 12 shell (ubuntu-24.04)'
                ;;
            *)
                printf '%s\tsuccess\n' \
                    'Test (ubuntu-24.04)' \
                    'Test (macos-14)' \
                    'Debian 12 shell (ubuntu-24.04)' \
                    'Debian 12 shell (ubuntu-24.04-arm)'
                ;;
        esac
        ;;
    *'conclusion == "success"'*)
        count=0
        [ ! -f "$PLASTICINE_TEST_GH_STATE" ] || count=$(cat "$PLASTICINE_TEST_GH_STATE")
        count=$((count + 1))
        printf '%s\n' "$count" > "$PLASTICINE_TEST_GH_STATE"
        case $PLASTICINE_TEST_SCENARIO:$count in
            wait:1|failed:*) ;;
            *) printf '%s\n' 101 ;;
        esac
        ;;
    *'status != "completed"'*)
        [ "$PLASTICINE_TEST_SCENARIO" != wait ] || printf '%s\n' 100
        ;;
    *'status == "completed"'*)
        [ "$PLASTICINE_TEST_SCENARIO" != failed ] || printf '%s\t%s\n' 102 failure
        ;;
    *)
        printf 'unexpected gh invocation: %s\n' "$*" >&2
        exit 98
        ;;
esac
EOF
chmod 755 "$test_root/gh"

run_gate() {
    scenario=$1
    : > "$test_root/calls"
    rm -f "$test_root/state"
    PLASTICINE_TEST_SCENARIO=$scenario \
    PLASTICINE_TEST_GH_CALLS=$test_root/calls \
    PLASTICINE_TEST_GH_STATE=$test_root/state \
    GH_BIN=$test_root/gh \
        "$gate" owner/repository "$revision" 5 0
}

wait_output=$(run_gate wait)
printf '%s\n' "$wait_output" | grep -Fqx "CI is still running for $revision; waiting..."
printf '%s\n' "$wait_output" | grep -Fqx "CI run 101 passed all required jobs for $revision"
grep -Fq "actions/workflows/ci.yml/runs?head_sha=$revision&event=push" "$test_root/calls"

set +e
missing_output=$(run_gate missing-job 2>&1)
missing_status=$?
set -e
[ "$missing_status" -eq 1 ]
printf '%s\n' "$missing_output" | grep -Fq 'successful CI run 101 is missing required job: Debian 12 shell (ubuntu-24.04-arm)'

set +e
failed_output=$(run_gate failed 2>&1)
failed_status=$?
set -e
[ "$failed_status" -eq 1 ]
printf '%s\n' "$failed_output" | grep -Fq "CI completed without success for $revision: 102 failure"

printf '%s\n' 'CI gate tests passed'
