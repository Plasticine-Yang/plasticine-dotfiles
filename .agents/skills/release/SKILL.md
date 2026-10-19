---
name: release
description: "Publish a base dotfiles release: pick the SemVer version, push main, dispatch the Release workflow immediately, watch it gate on CI, then verify assets and the published installer."
---

# Release

Publish a new stable Base Dotfiles release. The Release workflow owns tag creation, asset construction, draft verification, and publication; do not create tags or releases by hand.

## Steps

1. **Fix the version.** Read the latest stable release and choose the next SemVer version: a new Feature or any user-selectable behavior change is a minor bump, a fix-only release is a patch bump. Ask the user when the request is ambiguous. Completion: `$version` is newer than the latest stable and is not already tagged.

2. **Push the release commit.** Require a clean working tree on `main`, push it, and confirm `HEAD` equals the remote `main`. Do not wait for CI here: the workflow's "Reuse successful CI" step waits for the exact commit or requests a full run. Completion: `git rev-parse HEAD` equals the pushed `main` and `git status --porcelain` is empty.

3. **Dispatch immediately.** Run `gh workflow run release.yml -R <owner/repo> --ref main -f version=<version>` and capture the run id from the printed URL. The workflow validates the dispatch ref, version ordering, and the absence of the tag and release. If `gh` is unavailable or unauthenticated, stop and ask the user to run the workflow from the Actions page; do not fall back to manual tags. Completion: a Release run exists for the pushed commit.

4. **Watch the gate.** Run `gh run watch <run-id> -R <owner/repo> --exit-status`. On failure, read `gh run view <run-id> -R <owner/repo> --log-failed`, fix the cause, push a new commit, and return to step 1. A version whose tag or release already exists is burned; use the next patch version and get user approval before deleting anything. Completion: the run concludes successfully.

5. **Verify the Release.** Check that the tag points at the release commit, the Release is published rather than draft, immutable, marked latest, and has exactly five assets: `install.sh`, `plasticine-cli.tar.gz`, `plasticine-managed-plugins.tar.gz`, `plasticine-source.bundle`, `SHA256SUMS`. Download the assets, run `shasum -a 256 -c SHA256SUMS`, check that `sh install.sh --help` exposes the new flags, and clone the source bundle to confirm the new module and suites are present. Completion: every check passes.

6. **Smoke the published installer.** In a disposable `HOME`, run the released installer with the changed Feature flags, assert the installed command and Feature state, then rerun and assert the maintenance route. Confirm a standalone Feature created no shell startup files. Remove the disposable `HOME`. Completion: install and rerun both succeed with the expected route.

7. **Record the release.** Set the release ticket to `done` and append the version, tag commit, CI run URL, Release run URL, asset verification, and smoke results. Commit the ticket and docs with `docs(release): ...` and push; documentation-only pushes skip CI. Completion: the ticket is done, the commit is pushed, and `main` is clean.

## Reference

- Version policy: new Feature or selection change → minor; fix-only release → patch; never reuse a version whose tag or release exists.
- Resolve the repository with `gh repo view --json nameWithOwner -q .nameWithOwner`; resolve the release commit with `git rev-parse HEAD`.
- Repo release contract: README `## 发布`.
- Workflow: `.github/workflows/release.yml` validates the request, reuses or waits for CI, builds with `scripts/release-gate.sh`, creates a draft, verifies assets and digests, then publishes.
- Release inspection: `gh release view <version> -R <owner/repo> --json tagName,isDraft,isPrerelease,isImmutable,targetCommitish,publishedAt,assets`.
- Documentation-only commits (`.scratch/**`, `docs/**`, `README.md`) skip routine CI on `main`; a Release still requires CI for its exact commit and requests it when missing.
