#!/bin/sh
set -eu

timeout_seconds=${1:-}
test_name=${2:-}
if [ "$#" -lt 3 ]; then
    printf '%s\n' 'usage: scripts/run-test.sh <timeout-seconds> <test-name> <command> [argument ...]' >&2
    exit 2
fi
case $timeout_seconds in
    *[!0-9]*|'')
        printf '%s\n' 'test timeout must be a positive integer' >&2
        exit 2
        ;;
esac
[ "$timeout_seconds" -gt 0 ] || {
    printf '%s\n' 'test timeout must be a positive integer' >&2
    exit 2
}
[ -n "$test_name" ] || {
    printf '%s\n' 'test name must not be empty' >&2
    exit 2
}
shift 2

printf 'START test: %s\n' "$test_name"
started_at=$(date +%s)
# Test fixtures create disposable repositories and must not invoke the
# operator's global hooks or Trace2 sink. Command-scope overrides preserve
# HOME-scoped Git config tests while keeping local and CI execution equivalent.
GIT_CONFIG_COUNT=2
GIT_CONFIG_KEY_0=core.hooksPath
GIT_CONFIG_VALUE_0=/dev/null
GIT_CONFIG_KEY_1=trace2.eventTarget
GIT_CONFIG_VALUE_1=/dev/null
export GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 \
    GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
set +e
perl -MPOSIX=:sys_wait_h,setpgid -MTime::HiRes=time,sleep -e '
    my ($limit, @command) = @ARGV;
    my $pid = fork();
    die "fork failed: $!\n" unless defined $pid;
    if ($pid == 0) {
        setpgid(0, 0) or die "setpgid failed: $!\n";
        exec @command;
        die "exec failed: $!\n";
    }
    setpgid($pid, $pid);
    my $deadline = time() + $limit;
    while (waitpid($pid, WNOHANG) == 0) {
        if (time() >= $deadline) {
            # Notify the suite leader first so a shell blocked in wait can run
            # its cleanup trap. Its process group is cleaned up immediately
            # afterwards, including any grandchildren the suite left behind.
            kill "TERM", $pid;
            my $grace_deadline = time() + 0.5;
            while (waitpid($pid, WNOHANG) == 0 && time() < $grace_deadline) {
                sleep 0.05;
            }
            kill "TERM", -$pid;
            sleep 0.1;
            kill "KILL", -$pid;
            if (waitpid($pid, WNOHANG) == 0) {
                waitpid($pid, 0);
            }
            exit 124;
        }
        sleep 0.05;
    }
    exit(WIFEXITED($?) ? WEXITSTATUS($?) : 128 + WTERMSIG($?));
' "$timeout_seconds" "$@"
status=$?
set -e
elapsed=$(( $(date +%s) - started_at ))

case $status in
    0) printf 'PASS test: %s (%ss)\n' "$test_name" "$elapsed" ;;
    124) printf 'TIMEOUT test: %s (%ss limit)\n' "$test_name" "$timeout_seconds" >&2 ;;
    *) printf 'FAIL test: %s (exit %s)\n' "$test_name" "$status" >&2 ;;
esac
exit "$status"
