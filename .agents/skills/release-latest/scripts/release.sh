#!/bin/sh

set -eu

mode="release"
case "${1:-}" in
	"")
		;;
	--plan)
		mode="plan"
		;;
	*)
		printf 'usage: %s [--plan]\n' "$0" >&2
		exit 2
		;;
esac

remote="origin"
branch="main"
workflow="release.yml"
expected_repository="Plasticine-Yang/plasticine-dotfiles"

fail() {
	printf 'release-latest: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_clean_worktree() {
	if ! git diff --quiet --ignore-submodules -- ||
		! git diff --cached --quiet --ignore-submodules -- ||
		[ -n "$(git ls-files --others --exclude-standard)" ]; then
		fail "commit every intended change before publishing"
	fi
}

require_command git
require_command gh
require_command go

root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "run inside the plasticine-dotfiles repository"
cd "$root"

[ -x scripts/validate-release.sh ] || fail "scripts/validate-release.sh is missing or not executable"
[ -f .github/workflows/release.yml ] || fail ".github/workflows/release.yml is missing"
[ "$(git branch --show-current)" = "$branch" ] || fail "release from the $branch branch"

gh auth status >/dev/null 2>&1 || fail "GitHub CLI authentication is required"
[ "$(gh repo view --json nameWithOwner --jq '.nameWithOwner')" = "$expected_repository" ] ||
	fail "release only the $expected_repository repository"
git fetch "$remote" --tags --prune
git rev-parse --verify "$remote/$branch" >/dev/null 2>&1 || fail "$remote/$branch is unavailable"

divergence="$(git rev-list --left-right --count "HEAD...$remote/$branch")"
local_only="$(printf '%s\n' "$divergence" | awk '{ print $1 }')"
remote_only="$(printf '%s\n' "$divergence" | awk '{ print $2 }')"
[ "$remote_only" -eq 0 ] || fail "$remote/$branch is ahead; synchronize before releasing"
[ "$local_only" -ge 0 ] || fail "could not compare HEAD with $remote/$branch"

require_clean_worktree

head="$(git rev-parse HEAD)"
latest_tag="$(gh api "repos/{owner}/{repo}/releases/latest" --jq '.tag_name')" ||
	fail "could not resolve the latest published stable release"
printf '%s\n' "$latest_tag" |
	grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ||
	fail "latest published release is not a stable SemVer tag: $latest_tag"
git rev-parse --verify "refs/tags/$latest_tag" >/dev/null 2>&1 ||
	fail "latest published tag is missing locally after fetch: $latest_tag"

latest_commit="$(git rev-list -n 1 "$latest_tag")"
git merge-base --is-ancestor "$latest_commit" "$head" ||
	fail "HEAD does not descend from $latest_tag"

if [ "$head" = "$latest_commit" ]; then
	[ "$(git rev-parse "$remote/$branch")" = "$head" ] ||
		fail "$latest_tag is published but $remote/$branch points elsewhere"
	printf 'release-latest: HEAD is already published as %s\n' "$latest_tag"
	exit 0
fi

version="${latest_tag#v}"
major="${version%%.*}"
remainder="${version#*.}"
minor="${remainder%%.*}"
patch="${remainder#*.}"
next_tag="v${major}.${minor}.$((patch + 1))"

git rev-parse --verify "refs/tags/$next_tag" >/dev/null 2>&1 &&
	fail "next tag already exists locally: $next_tag"
if git ls-remote --exit-code --tags "$remote" "refs/tags/$next_tag" >/dev/null 2>&1; then
	fail "next tag already exists remotely: $next_tag"
fi
if gh release view "$next_tag" >/dev/null 2>&1; then
	fail "next release already exists: $next_tag"
fi

printf 'release-latest: %s -> %s at %s\n' "$latest_tag" "$next_tag" "$head"
if [ "$mode" = "plan" ]; then
	exit 0
fi

gate_log="$(mktemp)"
tag_created="0"
tag_pushed="0"
cleanup() {
	rm -f "$gate_log"
	if [ "$tag_created" = "1" ] && [ "$tag_pushed" = "0" ]; then
		if [ "$(git rev-parse -q --verify "refs/tags/$next_tag" 2>/dev/null || true)" = "$head" ] &&
			! git ls-remote --exit-code --tags "$remote" "refs/tags/$next_tag" >/dev/null 2>&1; then
			git tag -d "$next_tag" >/dev/null 2>&1 || true
		fi
	fi
}
trap cleanup EXIT HUP INT TERM

printf 'release-latest: validating %s\n' "$next_tag"
if PLASTICINE_VERSION="$next_tag" scripts/validate-release.sh >"$gate_log" 2>&1; then
	cat "$gate_log"
elif grep -q 'missing LC_UUID load command' "$gate_log"; then
	cat "$gate_log" >&2
	printf '%s\n' 'release-latest: retrying validation with the external macOS linker' >&2
	if ! GOFLAGS='-ldflags=-linkmode=external' PLASTICINE_VERSION="$next_tag" \
		scripts/validate-release.sh >"$gate_log" 2>&1; then
		cat "$gate_log" >&2
		fail "release validation failed"
	fi
	cat "$gate_log"
else
	cat "$gate_log" >&2
	fail "release validation failed"
fi

require_clean_worktree
[ "$(git rev-parse HEAD)" = "$head" ] || fail "HEAD changed during validation"

git fetch "$remote" --tags --prune
divergence="$(git rev-list --left-right --count "HEAD...$remote/$branch")"
remote_only="$(printf '%s\n' "$divergence" | awk '{ print $2 }')"
[ "$remote_only" -eq 0 ] || fail "$remote/$branch advanced during validation"
git rev-parse --verify "refs/tags/$next_tag" >/dev/null 2>&1 &&
	fail "next tag appeared during validation: $next_tag"
if git ls-remote --exit-code --tags "$remote" "refs/tags/$next_tag" >/dev/null 2>&1; then
	fail "next tag appeared remotely during validation: $next_tag"
fi

git tag "$next_tag" "$head"
tag_created="1"
git push --atomic "$remote" "HEAD:refs/heads/$branch" "refs/tags/$next_tag"
tag_pushed="1"

printf 'release-latest: waiting for %s workflow\n' "$next_tag"
run_id=""
attempt="0"
while [ -z "$run_id" ] && [ "$attempt" -lt 30 ]; do
	run_id="$(
		gh run list \
			--workflow "$workflow" \
			--event push \
			--commit "$head" \
			--limit 10 \
			--json databaseId,headBranch \
			--jq '.[] | select(.headBranch == "'"$next_tag"'") | .databaseId' |
			head -n 1
	)"
	if [ -z "$run_id" ]; then
		attempt=$((attempt + 1))
		sleep 2
	fi
done
[ -n "$run_id" ] || fail "release workflow did not appear for $next_tag"

gh run watch "$run_id" --exit-status --interval 10

release_tag="$(gh release view "$next_tag" --json tagName --jq '.tagName')"
release_draft="$(gh release view "$next_tag" --json isDraft --jq '.isDraft')"
release_prerelease="$(gh release view "$next_tag" --json isPrerelease --jq '.isPrerelease')"
[ "$release_tag" = "$next_tag" ] || fail "published release tag mismatch: $release_tag"
[ "$release_draft" = "false" ] || fail "release is still a draft: $next_tag"
[ "$release_prerelease" = "false" ] || fail "patch release was marked as a prerelease: $next_tag"

expected_assets="$(
	printf '%s\n' \
		checksums.txt \
		install.sh \
		plasticine_darwin_amd64 \
		plasticine_darwin_arm64 \
		plasticine_linux_amd64 \
		plasticine_linux_arm64 |
		LC_ALL=C sort
)"
actual_assets="$(
	gh release view "$next_tag" --json assets --jq '.assets[].name' |
		LC_ALL=C sort
)"
[ "$actual_assets" = "$expected_assets" ] ||
	fail "release asset set is incomplete for $next_tag"

latest_published="$(gh api "repos/{owner}/{repo}/releases/latest" --jq '.tag_name')"
[ "$latest_published" = "$next_tag" ] ||
	fail "latest stable release still resolves to $latest_published"

remote_main="$(git ls-remote "$remote" "refs/heads/$branch" | awk 'NR == 1 { print $1 }')"
remote_tag="$(git ls-remote "$remote" "refs/tags/$next_tag" | awk 'NR == 1 { print $1 }')"
[ "$remote_main" = "$head" ] || fail "remote $branch does not point to released commit"
[ "$remote_tag" = "$head" ] || fail "remote $next_tag does not point to released commit"

release_url="$(gh release view "$next_tag" --json url --jq '.url')"
run_url="$(gh run view "$run_id" --json url --jq '.url')"
printf 'release-latest: published %s\n' "$release_url"
printf 'release-latest: workflow %s\n' "$run_url"
