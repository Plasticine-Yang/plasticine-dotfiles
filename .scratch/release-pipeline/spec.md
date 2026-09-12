# Reproducible release pipeline

Status: done

## Goal

Publish this repository as an independent SemVer product, beginning at
`v0.1.0`, through a repeatable GitHub Actions workflow. A published installer
must always install the exact commit represented by its Release.

## Release model

- Pull requests and `main` run the same blocking test suite on Ubuntu and macOS.
- A maintainer starts a release manually from `main` and supplies a stable
  `vMAJOR.MINOR.PATCH` version.
- The release workflow validates the exact triggering commit before creating a
  tag or GitHub Release.
- Release assets are built and verified in CI. No local build output is trusted.
- The source installer follows its configured repository branch for development.
  The published installer embeds a full commit ID and checks out that commit.
- The Release contains `install.sh` and `SHA256SUMS`.
- Release publication is serialized and uses the minimum write permission.

## Verification boundary

The release gate includes POSIX syntax and ShellCheck, all repository test
suites, deterministic asset generation, checksum verification, and an install
smoke test against the pinned commit in a disposable HOME.

## Repository settings

Branch rules and immutable Releases are follow-up repository administration.
The checked-in workflows must be usable before those settings are enabled.
