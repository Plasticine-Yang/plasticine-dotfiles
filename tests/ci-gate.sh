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
    'workflow run ci.yml --repo owner/repository --ref main') ;;
    *'/git/ref/heads/main'*)
        case $PLASTICINE_TEST_SCENARIO in
            advanced) printf '%040d\n' 1 ;;
            *) printf '%s\n' 0123456789abcdef0123456789abcdef01234567 ;;
        esac
        ;;
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
    *'ci.yml/runs'*)
        count=0
        [ ! -f "$PLASTICINE_TEST_GH_STATE" ] || count=$(cat "$PLASTICINE_TEST_GH_STATE")
        count=$((count + 1))
        printf '%s\n' "$count" > "$PLASTICINE_TEST_GH_STATE"
        case $PLASTICINE_TEST_SCENARIO:$count in
            request:1|request:2|request-failed:1|advanced:*|empty:*) ;;
            request-failed:*) printf '%s\t%s\t%s\n' 102 completed failure ;;
            wait:1) printf '%s\t%s\t%s\n' 100 in_progress '' ;;
            failed:*) printf '%s\t%s\t%s\n' 102 completed failure ;;
            *) printf '%s\t%s\t%s\n' 101 completed success ;;
        esac
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
    PLASTICINE_REQUEST_MISSING_CI=1 \
    GH_BIN=$test_root/gh \
        "$gate" owner/repository "$revision" 5 0
}

wait_output=$(run_gate wait)
printf '%s\n' "$wait_output" | grep -Fqx "CI is still running for $revision; waiting..."
printf '%s\n' "$wait_output" | grep -Fqx "CI run 101 passed all required jobs for $revision"
grep -Fq "actions/workflows/ci.yml/runs?head_sha=$revision&per_page=100" "$test_root/calls"
grep -Fq 'select(.event == "push" or .event == "workflow_dispatch")' "$test_root/calls"
if grep -Fq 'workflow run' "$test_root/calls"; then exit 1; fi

request_output=$(run_gate request)
printf '%s\n' "$request_output" | grep -Fqx "Requested full CI for $revision"
printf '%s\n' "$request_output" | grep -Fqx "CI run 101 passed all required jobs for $revision"
[ "$(grep -Fc 'workflow run ci.yml' "$test_root/calls")" -eq 1 ]

set +e
request_failed_output=$(run_gate request-failed 2>&1)
request_failed_status=$?
set -e
[ "$request_failed_status" -eq 1 ]
printf '%s\n' "$request_failed_output" | grep -Fq "CI completed without success for $revision"
[ "$(grep -Fc 'workflow run ci.yml' "$test_root/calls")" -eq 1 ]

# The gate stays read-only unless Release explicitly requests missing CI.
: > "$test_root/calls"
rm -f "$test_root/state"
set +e
readonly_output=$(PLASTICINE_TEST_SCENARIO=empty \
    PLASTICINE_TEST_GH_CALLS=$test_root/calls PLASTICINE_TEST_GH_STATE=$test_root/state \
    PLASTICINE_REQUEST_MISSING_CI=0 GH_BIN=$test_root/gh \
    "$gate" owner/repository "$revision" 0 0 2>&1)
readonly_status=$?
set -e
[ "$readonly_status" -eq 1 ]
printf '%s\n' "$readonly_output" | grep -Fq 'timed out waiting for successful CI'
if grep -Fq 'workflow run' "$test_root/calls"; then exit 1; fi

set +e
advanced_output=$(run_gate advanced 2>&1)
advanced_status=$?
set -e
[ "$advanced_status" -eq 1 ]
printf '%s\n' "$advanced_output" | grep -Fq 'main advanced before CI could be requested'
if grep -Fq 'workflow run' "$test_root/calls"; then exit 1; fi

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
