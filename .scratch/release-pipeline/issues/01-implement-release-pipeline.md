# Implement the reproducible release pipeline

Status: done

## Requirements

- Add CI for pull requests and `main` on Ubuntu and macOS.
- Add a manually dispatched stable release workflow.
- Generate an installer pinned to the release commit without modifying the
  source checkout.
- Verify the exact generated assets before publication.
- Document the release process and keep the first version independent at
  `v0.1.0`.
- Do not create a tag or Release while implementing the pipeline.

## Completion criteria

- The installer, release scripts, and workflow files have automated coverage.
- All existing tests and the new release tests pass.
- The local issue transitions to `done` after verification.

## Comments

- Added Ubuntu/macOS CI and a serialized, manually dispatched stable Release workflow.
- Release assets embed a full commit ID and are tested across both fresh installs and upgrades from an older detached release.
- The workflow creates a draft, verifies its target and uploaded asset digest, then publishes it and verifies the resulting tag.
- Local ShellCheck, actionlint, release tests, and all existing suites pass.
