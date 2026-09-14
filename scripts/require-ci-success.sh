#!/bin/sh
set -eu

repository=${1:-}
revision=${2:-}
wait_seconds=${3:-600}
poll_seconds=${4:-10}
gh_bin=${GH_BIN:-gh}

if [ -z "$repository" ] || [ -z "$revision" ]; then
    printf '%s\n' 'usage: scripts/require-ci-success.sh <owner/repository> <full-commit-id> [wait-seconds] [poll-seconds]' >&2
    exit 2
fi
case $revision in
    *[!0-9a-f]*|'')
        printf '%s\n' 'CI revision must be a full 40-character lowercase commit ID' >&2
        exit 2
        ;;
esac
[ "${#revision}" -eq 40 ] || {
    printf '%s\n' 'CI revision must be a full 40-character lowercase commit ID' >&2
    exit 2
}
case $wait_seconds in
    *[!0-9]*|'')
        printf '%s\n' 'CI wait and poll durations must be non-negative integers' >&2
        exit 2
        ;;
esac
case $poll_seconds in
    *[!0-9]*|'')
        printf '%s\n' 'CI wait and poll durations must be non-negative integers' >&2
        exit 2
        ;;
esac

runs_endpoint="repos/$repository/actions/workflows/ci.yml/runs?head_sha=$revision&event=push&per_page=100"
started_at=$(date +%s)

while :; do
    successful_run=$(
        "$gh_bin" api --method GET "$runs_endpoint" \
            --jq '.workflow_runs[] | select(.conclusion == "success") | .id' |
            sed -n '1p'
    )
    if [ -n "$successful_run" ]; then
        jobs_file=$(mktemp "${TMPDIR:-/tmp}/plasticine-ci-jobs.XXXXXX")
        trap 'rm -f "$jobs_file"' EXIT HUP INT TERM
        "$gh_bin" api --method GET \
            "repos/$repository/actions/runs/$successful_run/jobs?per_page=100" \
            --paginate --jq '.jobs[] | [.name, (.conclusion // "")] | @tsv' > "$jobs_file"

        for required_job in \
            'Test (ubuntu-24.04)' \
            'Test (macos-14)' \
            'Debian 12 shell (ubuntu-24.04)' \
            'Debian 12 shell (ubuntu-24.04-arm)'; do
            if ! conclusion=$(awk -F '\t' -v required="$required_job" \
                '$1 == required { print $2; found=1; exit } END { if (!found) exit 1 }' \
                "$jobs_file"); then
                printf 'successful CI run %s is missing required job: %s\n' \
                    "$successful_run" "$required_job" >&2
                exit 1
            fi
            [ "$conclusion" = success ] || {
                printf 'required CI job did not succeed: %s (%s)\n' \
                    "$required_job" "$conclusion" >&2
                exit 1
            }
        done
        rm -f "$jobs_file"
        trap - EXIT HUP INT TERM
        printf 'CI run %s passed all required jobs for %s\n' "$successful_run" "$revision"
        exit 0
    fi

    pending_run=$(
        "$gh_bin" api --method GET "$runs_endpoint" \
            --jq '.workflow_runs[] | select(.status != "completed") | .id' |
            sed -n '1p'
    )
    if [ -z "$pending_run" ]; then
        completed_run=$(
            "$gh_bin" api --method GET "$runs_endpoint" \
                --jq '.workflow_runs[] | select(.status == "completed") | [.id, (.conclusion // "unknown")] | @tsv' |
                sed -n '1p' | tr '\t' ' '
        )
        if [ -n "$completed_run" ]; then
            printf 'CI completed without success for %s: %s\n' \
                "$revision" "$completed_run" >&2
            exit 1
        fi
    fi

    now=$(date +%s)
    [ $((now - started_at)) -lt "$wait_seconds" ] || {
        printf 'timed out waiting for successful CI for %s\n' "$revision" >&2
        exit 1
    }
    if [ -n "$pending_run" ]; then
        printf 'CI is still running for %s; waiting...\n' "$revision"
    else
        printf 'CI has not started for %s; waiting...\n' "$revision"
    fi
    sleep "$poll_seconds"
done
