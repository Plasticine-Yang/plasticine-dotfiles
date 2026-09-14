#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
ci=$repo_dir/.github/workflows/ci.yml
release=$repo_dir/.github/workflows/release.yml

for suite in integration combined-installation chezmoi git-config installer shell \
    shell-runtime lazygit lazygit-runtime fnm fnm-runtime neovim neovim-runtime \
    herdr release release-payload test-runner workflows ci-gate; do
    grep -Eq "scripts/run-test\.sh [0-9]+ $suite (\./)?tests/$suite\.sh" "$ci" || {
        printf 'CI does not run %s through the timeout runner\n' "$suite" >&2
        exit 1
    }
done

# Timed-out suites can orphan descendants. Debian containers need an init
# process to reap them, just as the non-container CI runners do.
perl -0777ne 'exit(/container:\s*\n\s+image: debian:12-slim\s*\n\s+options: --init\s*\n/ ? 0 : 1)' "$ci" || {
    printf '%s\n' 'Debian CI container must use --init to reap orphaned test processes' >&2
    exit 1
}

if grep -Fq 'uses: ./.github/workflows/ci.yml' "$release"; then
    printf '%s\n' 'Release still reruns the complete CI workflow' >&2
    exit 1
fi
grep -Fq 'actions: read' "$release"
# shellcheck disable=SC2016
grep -Fq './scripts/require-ci-success.sh "$GITHUB_REPOSITORY" "$RELEASE_SHA"' "$release"
# shellcheck disable=SC2016
grep -Fq './scripts/release-gate.sh "$RELEASE_SHA" dist "$VERSION" "$GITHUB_WORKSPACE"' "$release"

printf '%s\n' 'workflow tests passed'
