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

runs_file=$(mktemp "${TMPDIR:-/tmp}/plasticine-ci-runs.XXXXXX")
jobs_file=''
cleanup() {
    rm -f "$runs_file"
    [ -z "$jobs_file" ] || rm -f "$jobs_file"
}
trap cleanup EXIT HUP INT TERM

while :; do
    # Take one snapshot per poll. Deriving "successful" and "pending" from
    # separate API calls races a run that completes in between: the successful
    # query misses it and the completed query then reports a false failure.
    if ! "$gh_bin" api --method GET "$runs_endpoint" --paginate \
        --jq '.workflow_runs[] | [.id, .status, (.conclusion // "")] | @tsv' > "$runs_file"; then
        printf 'could not query CI runs for %s\n' "$revision" >&2
        exit 1
    fi

    successful_run=$(awk -F '\t' '$2 == "completed" && $3 == "success" { print $1; exit }' "$runs_file")
    if [ -n "$successful_run" ]; then
        jobs_file=$(mktemp "${TMPDIR:-/tmp}/plasticine-ci-jobs.XXXXXX")
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
        printf 'CI run %s passed all required jobs for %s\n' "$successful_run" "$revision"
        exit 0
    fi

    pending_run=$(awk -F '\t' '$2 != "completed" { print $1; exit }' "$runs_file")
    if [ -z "$pending_run" ]; then
        completed_run=$(awk -F '\t' '$2 == "completed" { print $1 " " $3; exit }' "$runs_file")
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
