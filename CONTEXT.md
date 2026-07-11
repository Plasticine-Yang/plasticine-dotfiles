# Workstation Bootstrap

This context describes how a fresh or existing macOS/Linux workstation is brought to the repository's intended state and kept there safely.

## Language

**Owner**:
The single person whose preferences define the intended state of every managed workstation. This describes whose configuration the CLI embodies, not who is allowed to run it.
_Avoid_: Customer, supported user

**Desired State**:
The single opinionated catalog of Component definitions declared by a Release, with explicit platform branches and no machine-local value overrides. A Workstation Scope selects which Components apply on one machine without redefining them.
_Avoid_: Profile, local value override

**Workstation Scope**:
The persisted exclusion set identifying which Desired State Components Reconciliation leaves inactive on one Workstation. Components are enabled unless excluded.
_Avoid_: Profile, one-run component filter

**Suspended Component**:
A previously managed Component currently excluded by the Workstation Scope. Reconciliation preserves its content, ownership, and backups without inspecting or changing it until it is enabled again.
_Avoid_: Uninstalled Component, unmanaged state

**Retirement**:
A planned transition that removes owned artifacts which no longer belong to the selected Desired State. It is distinct from suspension: only unchanged managed content can retire directly, while Owner drift becomes a Conflict.
_Avoid_: Suspension, automatic cleanup

**Tool Lock**:
The Release input that fixes each Managed Tool artifact's version, platform URL, and SHA-256 digest. It is build-validated data rather than Owner-editable Workstation configuration.
_Avoid_: Local config, package-manager version

**Reference Configuration**:
Owner-maintained configuration kept in the repository for manual consultation or copying, outside the Desired State, Release, Plan, and Managed Path lifecycle.
_Avoid_: Component, optional profile

**Workstation**:
A macOS or Linux machine being converged to the Owner's intended state.
_Avoid_: Customer machine

**Plasticine Home**:
The Owner-only `~/.plasticine` root containing every persistent binary, Managed Tool payload, managed configuration body, cache, backup, Reconciliation State, and relocated Tool-managed State associated with plasticine. Conventional paths outside it contain only integration shims that tools require.
_Avoid_: Repository checkout, scattered XDG roots

**Release**:
An immutable, versioned snapshot of the Workstation CLI together with all non-secret configuration assets it reconciles. A Release never resolves configuration from a moving source branch at runtime.
_Avoid_: Latest main, repository checkout

**Artifact Target**:
A finite operating-system and architecture pair for which a Release publishes a Workstation CLI binary and Tool Lock entries. OS distribution versions do not create additional Artifact Targets.
_Avoid_: Supported distribution, CI runner

**Support Floor**:
The oldest release of a named operating-system family covered by the full Reconciliation contract. CI samples that contract with a finite matrix rather than treating every newer point release as a distinct target.
_Avoid_: Artifact Target, best-effort version

**Workstation CLI**:
The self-contained `plasticine` executable that plans and performs Reconciliation. It is built ahead of time for each Artifact Target and does not require its development toolchain on the Workstation.
_Avoid_: Go project, runtime script

**Secret**:
A sensitive value supplied locally to a Workstation when needed. It is never part of the repository, a Release, reconciliation state, backups, plans, or logs.
_Avoid_: Versioned environment configuration

**Secret Reference**:
Non-sensitive metadata that locates and identifies an Owner-managed Secret without containing it, such as an absolute private-key path and public fingerprint. It may be retained so Reconciliation can validate the external Secret repeatedly.
_Avoid_: Secret copy, credential

**Reconciliation State**:
Versioned local metadata recording Managed Path ownership, the applied Release, backups, and Secret References. It supports planning but never overrides the Workstation state actually observed.
_Avoid_: Desired State, local configuration

**System Change**:
A reconciliation operation that modifies system-owned state and therefore needs explicit authorization and narrowly scoped privilege escalation.
_Avoid_: Privileged run

**Managed Tool**:
A command-line tool whose installed version and configuration are part of the intended Workstation state declared by a Release.
_Avoid_: Prerequisite, manually installed dependency

**System Dependency**:
Operating-system software whose presence and minimum required capability are part of the Desired State, while its exact version remains owned by the native package manager.
_Avoid_: Managed Tool, pinned system package

**Tool-managed State**:
Plugins, caches, generated files, and similar content that Zsh, Neovim, or another Managed Tool resolves through its native mechanisms after configuration. It is outside Desired State, Plan, drift detection, and Release version guarantees.
_Avoid_: Managed Path, Release payload

**Component**:
A dependency-scoped unit of intended Workstation state that can be planned, applied, and verified independently.
_Avoid_: Setup step, install flag

**Managed Path**:
A filesystem path whose intended content and ownership have been accepted into Reconciliation state.
_Avoid_: Dotfile, symlink target

**Managed Block**:
A uniquely marked section inside an otherwise Owner-controlled text file. Reconciliation owns only the marked content and preserves every byte outside it.
_Avoid_: Managed Path, free-form merge

**Conflict**:
Existing content that cannot be preserved while executing the Plan and does not match the last content accepted by Reconciliation. It includes both an unmanaged path that differs from Desired State and Owner drift on a Managed Path being replaced or retired, and blocks until the Owner explicitly authorizes resolution.
_Avoid_: Ordinary Release update, automatic backup

**Bootstrap**:
The minimal entrypoint that obtains and launches a selected release of the Workstation CLI. It does not configure the workstation itself.
_Avoid_: Installer, setup script

**Reconciliation**:
A run that converges the workstation toward the selected configuration and reports what changed or failed; repeating it is expected to be safe.
_Avoid_: One-time install

**Apply**:
The Reconciliation operation used for both an empty Workstation and every later run. Its result depends on current drift, not on whether the Workstation has been initialized before.
_Avoid_: Init, first-run setup

**Plan**:
The complete, read-only description of changes and blockers produced from the observed Workstation and a Release. Apply executes this same description after authorization rather than discovering additional work while mutating.
_Avoid_: Dry run, preview log
