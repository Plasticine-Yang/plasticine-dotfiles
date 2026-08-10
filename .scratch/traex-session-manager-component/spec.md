# Self-managed Traex Session Manager Component

Status: ready-for-agent

## Problem Statement

The Owner wants `traex-session-manager` (`tsm`) available on every managed Workstation without making its installed version part of Plasticine's Release-pinned Desired State. Today Plasticine can install version-pinned Managed Tools, but it has no way to bootstrap a tool once and then let that tool own its executable paths, versions, and native self-update lifecycle.

Treating TSM as a Managed Tool would make a native `tsm self-update` look like drift and could cause a later Apply to restore an older Tool Lock version. Leaving TSM completely outside Plasticine would require a separate manual workstation setup step. The Owner needs a third lifecycle: Plasticine ensures that the tool can initially be installed and repaired when unusable, while all continuing tool maintenance belongs to TSM.

## Solution

Add `traex-session-manager` as a default-enabled Component and introduce Self-managed Tool as a reusable Desired State category. When the Component is active, Reconciliation accepts an existing runnable `~/.local/bin/tsm`; otherwise, it plans and runs the Release-declared HTTPS upstream installer. The installer operation is explicit but opaque in Plan, uses ordinary Apply authorization, is bounded to two minutes, exposes its output, and fails independently from unrelated Components.

After a successful bootstrap or repair, Plasticine relinquishes ownership. It does not pin or record the TSM version, own or drift-check TSM paths, manage aliases, remind the Owner about updates, run self-update, back up TSM content, or remove TSM when the Component is excluded or retired. The Owner updates it explicitly through `tsm self-update`.

## User Stories

1. As the Owner, I want TSM represented as a Plasticine Component, so that a new Workstation receives the session manager through the same reconciliation flow as my other workstation capabilities.
2. As the Owner, I want the Component named `traex-session-manager`, so that Plan, Apply, Doctor, and the TUI identify the capability clearly rather than exposing only an executable filename.
3. As the Owner, I want the Component enabled by default, so that every Workstation receives TSM unless I explicitly exclude it through Workstation Scope.
4. As the Owner, I want the Component supported on macOS amd64, macOS arm64, Linux amd64, and Linux arm64, so that it follows Plasticine's complete Artifact Target matrix.
5. As the Owner provisioning a fresh Workstation, I want Apply to run TSM's upstream installer when `~/.local/bin/tsm` is absent, so that I do not need a separate installation step.
6. As the Owner with an existing TSM installation, I want Plasticine to accept it when `tsm --version` succeeds, so that reconciliation does not replace a working tool.
7. As the Owner with a native self-updated TSM installation, I want Apply to leave its version untouched, so that Plasticine never downgrades it to a Release-pinned version.
8. As the Owner with a broken TSM executable, I want Apply to rerun the upstream installer when `tsm --version` fails, so that the Component can restore its minimum promise that TSM runs.
9. As the Owner, I want TSM to own `~/.local/bin/tsm` after installation, so that its native updater can replace the executable without causing Plasticine drift.
10. As the Owner, I want to update TSM explicitly with `tsm self-update`, so that TSM controls its own version lifecycle.
11. As the Owner, I do not want Plasticine to check whether a newer TSM release exists, so that Doctor and Apply do not add unnecessary update traffic or reminders.
12. As the Owner, I want Plasticine to ignore the `traex-session-manager` alias, so that a convenience symlink does not become part of Component health or repair behavior.
13. As the Owner, I want an existing runnable TSM accepted without `--adopt`, so that an unowned Self-managed Tool is not treated like conflicting Managed Path content.
14. As the Owner, I want Plan to state that it will run an external TSM installer, so that the important mutation and trust decision is visible before Apply.
15. As the Owner, I want Plan to display the installer URL and external-script risk, so that I know which upstream entrypoint the Release trusts.
16. As the Owner, I accept that Plan cannot enumerate the mutable installer's internal files or exact selected version, so that TSM can retain its native latest-release installation flow.
17. As the Owner, I want Plan to remain offline, so that generating a Plan does not depend on temporary GitHub availability.
18. As the Owner, I want Plan to check the installer's local prerequisites, so that missing `curl`, `tar`, or a SHA-256 verification command is discovered before the external installer begins.
19. As the Owner on supported Linux, I want missing installer prerequisites handled through the existing System Dependency flow, so that native packages remain owned by the operating-system package manager.
20. As the Owner, I want existing System Change authorization rules to apply when installing missing system packages, so that `--yes` alone does not silently authorize privileged package changes.
21. As the Owner, I want the TSM installer itself authorized by the ordinary Apply confirmation or `--yes`, so that I do not need a new one-off authorization flag.
22. As the Owner, I want the remote script downloaded to a temporary file before execution, so that execution and failures are easier to inspect than a `curl | sh` pipeline.
23. As the Owner, I want the installer to inherit my normal `HOME`, `PATH`, and proxy environment, so that its documented installation behavior works consistently.
24. As the Owner, I want installer stdout and stderr visible while Apply runs, so that progress and failures are diagnosable.
25. As the Owner, I want Ctrl-C to cancel an active installation safely, so that I retain control of an interactive Apply or TUI session.
26. As the Owner, I want the installer bounded to two minutes, so that a stalled upstream process cannot hang Reconciliation indefinitely.
27. As the Owner, I want an installer failure reported against `traex-session-manager`, so that the failed capability is easy to identify.
28. As the Owner, I want independent Components to continue after a TSM installation failure, so that one external tool does not block unrelated workstation configuration.
29. As the Owner, I want Plasticine to avoid guessed rollback of a failed installer, so that it does not damage paths whose internal mutation contract it does not own.
30. As the Owner, I want the next Apply to observe the actual executable again and retry when needed, so that recovery follows current Workstation state rather than remembered assumptions.
31. As the Owner, I want Doctor to check only whether the active Component's primary `tsm` executable can report its version, so that health reflects the minimal Self-managed Tool contract.
32. As the Owner, I want Doctor to ignore TSM version freshness and aliases, so that Plasticine does not over-manage tool-owned behavior.
33. As the Owner excluding the Component from Workstation Scope, I want Plasticine to stop observing and bootstrapping TSM, so that the excluded capability is left entirely alone.
34. As the Owner excluding a previously installed TSM Component, I want its executable preserved, so that Scope suspension is not mistaken for uninstallation.
35. As the Owner upgrading to a Release that no longer contains the Component, I want the TSM installation preserved, so that Plasticine does not retire paths it never owned.
36. As the Owner, I do not want TSM executable paths, versions, or bootstrap history recorded in Reconciliation State, so that self-managed state cannot later be mistaken for Plasticine ownership.
37. As the Owner, I want the installer URL declared by the immutable Plasticine Release, so that the trusted upstream entrypoint remains reviewable.
38. As the Owner, I want Self-managed Tool installer URLs restricted to HTTPS and protected from machine-local overrides, so that local configuration cannot redirect Apply to an unreviewed script source.
39. As the Owner, I want the Self-managed Tool lifecycle reusable for a future tool with the same ownership model, so that TSM does not introduce a growing collection of product-specific Reconciliation branches.
40. As a maintainer, I want the reusable lifecycle to stay deliberately small, so that adding TSM does not attempt to generalize arbitrary package managers or installer protocols.

## Implementation Decisions

- Add Self-managed Tool as a reusable Desired State category distinct from Managed Tool, System Dependency, and Tool-managed State. A Self-managed Tool has a Release-declared bootstrap contract, but its executable paths and continuing lifecycle are not owned by Reconciliation.
- Add a default-enabled `traex-session-manager` Component with no Component dependency. It participates in the existing Workstation Scope, one-run Component filtering, component ordering, progress, Result, CLI, and TUI behavior.
- Support the Component on all four current Artifact Targets. Platform support follows the upstream installer; a target-specific installer failure is an operational failure for this Component rather than a global unsupported-target result.
- Define a minimal Release-owned Self-managed Tool descriptor containing the Component identity, HTTPS installer URL, fixed primary executable path, health command, prerequisite capabilities, and execution timeout. Do not expose installer internals or machine-local values through this interface.
- Treat `~/.local/bin/tsm` as the only primary executable. A successful `tsm --version` satisfies planning and Doctor health regardless of reported version. PATH resolution and the `traex-session-manager` alias do not participate in detection.
- Use the reviewed upstream `traex-session-manager` installation script URL declared in Desired State. Do not add TSM to Tool Lock, do not add seed metadata, and do not checksum or pin the mutable script as part of this feature.
- Plan a distinct external-installer change only when the primary executable is missing or the health command fails. The Change representation must identify the Component, installer URL, external-script risk, and opaque nature of downstream modifications without pretending to enumerate them.
- Plan performs no network request for this lifecycle. It checks only local platform support, Component activity, executable health, and installer prerequisites.
- Add explicit prerequisite capabilities for `curl`, `tar`, and a usable SHA-256 verifier. A verifier is satisfied by either `shasum` or `sha256sum`. Supported Linux hosts use the existing System Dependency mechanism and authorization when native packages are required; supported macOS hosts report Owner action when a prerequisite is unavailable.
- External installer execution uses ordinary Apply authorization. It does not add a new risk-specific CLI flag or authorization decision field. Existing System Changes needed for prerequisites still require their existing separate authorization.
- Apply downloads the installer over HTTPS into a private temporary location and executes that file rather than piping network content directly into a shell.
- Installer execution inherits the Workstation's normal `HOME`, `PATH`, proxy environment, and other ordinary process environment needed by the upstream script. Its stdout and stderr remain visible to CLI and TUI users.
- Installer execution honors the Reconciliation context and safe TUI cancellation behavior and has a two-minute timeout. Temporary files are cleaned after success, failure, cancellation, or timeout.
- After the installer exits successfully, Apply reruns the primary health command. The Component succeeds only if `tsm --version` now exits successfully.
- Installer download, execution, timeout, cancellation, and post-install health failures are operational failures attributed to `traex-session-manager`. Existing dependency and component failure rules continue independent Components and skip only actual dependents.
- Plasticine performs no speculative rollback of upstream installer effects. A later Plan and Apply observe the current primary executable and decide again from that state.
- Accept any existing runnable primary executable without conflict, backup, adoption, version comparison, ownership, or state migration.
- Do not create Ownership entries, pending-work journal entries describing tool-owned paths, Secret References, version records, or bootstrap-history state for TSM.
- Excluding the Component stops Plan, Apply, and Doctor from observing or operating on TSM. Re-enabling it resumes observation from current Workstation state.
- Removing the Component from a future catalog produces no Retirement for TSM paths because those paths were never Managed Paths or Managed Tool payloads.
- Doctor runs only the primary health command for an active Component. It reports healthy or unhealthy execution without network access, version comparison, alias checks, or update advice.
- CLI and TUI render the external installer as an explicit risky opaque change, show component-scoped progress and failures, and preserve the existing ordinary confirmation and `--yes` behavior.
- The new lifecycle is a narrow documented exception to complete Plan detail, Plasticine Home ownership, and Tool Lock-only Apply network egress, as recorded in ADR 0066.
- Adding the Component changes the Desired State identity through the existing stable component catalog mechanism; it does not change the Reconciliation State schema merely to record Self-managed Tool history.

## Testing Decisions

- The primary and highest test seam is the Reconciler's public Plan, Apply, and Doctor behavior. Tests exercise an isolated Plasticine Home and Workstation Root and assert only observable Results, progress, executed effects, and final filesystem state.
- Reconciler contract tests are the prior art. Existing tests already cover immutable authorization, Managed Tool downloads, System Dependency application, independent Component continuation, Scope suspension, Retirement, Doctor checks, cancellation-facing progress, and state ownership.
- Keep external dependencies deterministic: use a local HTTP server for installer downloads and a command execution test adapter that simulates installer success, failure, timeout, cancellation, visible output, and creation of a runnable fixture executable. Tests must never access real GitHub or execute a real remote script.
- Test that Plan reports one opaque external-installer change with the reviewed HTTPS URL when the primary executable is absent, while making no HTTP request.
- Test that Plan reports no TSM change when the fixed primary executable exists and its version command succeeds, regardless of the version text it emits.
- Test that a primary executable outside the fixed path does not satisfy the Component.
- Test that a present but non-executable primary path and a failing version command both plan repair.
- Test that missing `curl`, `tar`, or both supported SHA-256 verifier commands is discovered during Plan and represented through existing capability and System Dependency outcomes.
- Test ordinary authorization denial before installer download or execution, and test that `--yes` permits the external installer without a new authorization class.
- Test successful Apply downloads to a temporary file, invokes the installer with the expected environment, exposes progress, validates post-install health, and leaves no Plasticine ownership or bootstrap-history state for TSM paths.
- Test that visible installer output reaches the configured user-facing execution seam without asserting on internal buffering details.
- Test timeout and context cancellation independently, including temporary-file cleanup and absence of a successful Component result.
- Test download failure, installer nonzero exit, and post-install health failure as separate operational failure cases.
- Test that TSM failure produces a partial outcome while an unrelated Component still succeeds.
- Test that Apply does not attempt rollback after an installer has produced partial tool-owned state.
- Test that a later Apply retries when the primary executable remains unhealthy and becomes a no-op once it is runnable.
- Test that a native replacement or self-update of a runnable executable is accepted without drift, backup, adoption, cleanup, or downgrade.
- Test that Doctor checks only the fixed primary executable, reports an unhealthy Component when it cannot run, and performs no HTTP request or version-freshness comparison.
- Test that a missing or broken long-name alias has no effect on Plan, Apply, or Doctor.
- Test that Workstation Scope exclusion suppresses all TSM observation and installation while preserving existing tool-owned files, and that re-enabling observes current state.
- Test catalog removal behavior at the Reconciler seam to prove TSM paths are not retired or deleted.
- Test the Component catalog and Desired State identity include `traex-session-manager` consistently on all supported targets.
- Add thin CLI and TUI rendering tests only for the new externally visible representation: Component name, external-script risk, installer progress/failure, and next action. Do not duplicate Reconciler lifecycle tests at those lower-value seams.
- Good tests describe the ownership and lifecycle contract and survive internal refactoring. They must not assert private helper calls, temporary implementation types, exact internal function decomposition, or TSM's own installer and self-update implementation.

## Out of Scope

- Pinning a TSM version or adding TSM to Tool Lock.
- Adding a checksum-verified seed version or separate seed metadata.
- Automatically invoking `tsm self-update` from Plan, Apply, Doctor, TUI startup, shell startup, or TSM startup.
- Checking for newer TSM releases, comparing versions, or reminding the Owner that an update exists.
- Modifying the `traex-session-manager` repository, installer, release workflow, or self-update implementation.
- Verifying, pinning, vendoring, interpreting, or statically analyzing the mutable upstream installation script.
- Managing, repairing, or diagnosing the `traex-session-manager` long-name alias.
- Owning, backing up, adopting, drift-checking, journaling, migrating, retiring, uninstalling, or rolling back TSM-controlled files.
- Redirecting TSM into Plasticine Home or changing its documented `~/.local/bin` installation convention.
- Allowing installer URLs, paths, health commands, timeouts, or other Desired State values to be overridden per Workstation.
- Introducing a general package-manager abstraction or supporting arbitrary interactive third-party installers.
- Adding a new external-installer authorization flag or changing existing System Change authorization.
- Adding machine-readable CLI output.

## Further Notes

- ADR 0066 records the Self-managed Tool ownership decision and its narrow exceptions to ADR 0014, ADR 0054, and ADR 0060.
- The feature intentionally makes a weaker reproducibility promise than Managed Tool installation. Reproducibility ends at the reviewed installer entrypoint and execution contract; the selected TSM release and resulting tool-owned files remain upstream concerns.
- The upstream installer currently installs `tsm` under `~/.local/bin` and creates a long-name alias. Only the primary executable participates in this specification.
- After this spec, use `/to-tickets` to split the work into blocker-aware tracer-bullet implementation issues before running `/implement`.
