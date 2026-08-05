---
name: release-latest
description: Commit the current repository changes and publish the next stable patch release.
disable-model-invocation: true
---

# Release Latest

Ship one **immutable** patch Release from `main`. The repository workflow remains
the source of truth; this skill prepares one clean commit and drives that workflow
to a verified GitHub Release.

## 1. Seal the candidate

Inspect `git status`, the complete diff, recent commits, and the latest tag.

- Account for every modified and untracked file. Stage only intended source
  changes; leave credentials, local state, and generated release assets outside
  the commit.
- If the worktree contains changes, create one Conventional Commit describing
  the release candidate. End its message with exactly one:

  `Co-authored-by: TRAE CLI <noreply@bytedance.com>`

- If the worktree is already clean, release the current `HEAD`; do not manufacture
  an empty commit.

This step is complete when `main` has a clean worktree and `HEAD` contains every
intended change.

## 2. Pin the release

Run:

```sh
.agents/skills/release-latest/scripts/release.sh --plan
```

The script fetches `origin`, compares `main`, reads the latest published stable
Release, and derives the next patch tag. Stop on any preflight failure and report
the exact blocker.

This step is complete when the script prints `<latest-tag> -> <next-tag>` for the
current `HEAD`, or reports that `HEAD` is already published.

## 3. Publish

When the plan identifies a new patch tag, run:

```sh
.agents/skills/release-latest/scripts/release.sh
```

The script runs the full release gate, atomically pushes `main` and the tag,
watches `.github/workflows/release.yml`, and verifies:

- the workflow succeeded;
- the Release is stable and published;
- all four binaries, `checksums.txt`, and `install.sh` exist;
- GitHub's latest stable Release resolves to the new tag;
- remote `main` and the tag point to the released commit.

The tag and published assets are immutable. If a failure occurs after the atomic
push, preserve them and report the workflow diagnostics instead of rewriting
history.

This step is complete only when the script prints both the Release URL and the
successful workflow URL.

## 4. Report

Return the commit SHA and subject, tag, Release URL, workflow result, validation
result, and final `git status --short --branch`.

The run is complete when the reported commit, remote `main`, tag, and published
Release all identify the same commit and the worktree is clean.
