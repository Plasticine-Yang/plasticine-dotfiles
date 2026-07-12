# Plasticine CLI Antidote Integration

Status: ready-for-agent

## Problem Statement

The current `shell` Component materializes a central Zsh configuration and sets `ANTIDOTE_HOME`, but it does not install Antidote, declare any Zsh plugins, or load a generated plugin bundle. A freshly reconciled Workstation therefore receives the Plasticine Zsh shim and Managed Tool PATH, but not the intended Zsh plugin-manager experience.

The missing work must preserve Plasticine's existing trust boundary. Plasticine should pin and verify Antidote itself as Release-owned infrastructure, while leaving Antidote's plugin clones, generated static bundle, snapshots, compinit artifacts, and compiled files as Tool-managed State.

## Solution

Extend Managed Tool materialization to support directory payloads, then add Antidote as a Release-pinned Managed Tool owned by the `shell` Component. The shell Desired State will materialize a managed plugin declaration file and a Zsh bootstrap that sources the pinned Antidote payload, relocates Antidote runtime state under Plasticine Home, regenerates a static plugin bundle only when the declaration changes, and sources that generated bundle for interactive shells.

The public Component graph remains unchanged: `shell` continues to be the only user-facing Component for Zsh behavior. Antidote is implementation detail of `shell`, not a new Component selector. Generated plugin state is explicitly excluded from ownership, drift, backup, Retirement, and Doctor enumeration.

## User Stories

1. As an Owner, I want a freshly reconciled Workstation to receive a working Antidote-backed Zsh environment, so that the managed Zsh shell is useful without manual plugin-manager setup.
2. As an Owner, I want Antidote itself pinned by Tool Lock and verified by SHA-256, so that the plugin manager version changes only through reviewed Release edits.
3. As an Owner, I want source-only Managed Tools to install complete versioned directories, so that Zsh-native tools such as Antidote can keep their required sibling files and functions together.
4. As an Owner, I want the managed Zsh config to use a stable Antidote source shim, so that version switches update one managed target rather than scattering versioned paths through startup code.
5. As an Owner, I want the Zsh plugin declaration to be managed Desired State, so that my ordinary Workstations share the same plugin list without machine-local profiles.
6. As an Owner, I want Antidote's plugin clones, generated static bundle, snapshots, compinit dumps, and compiled files to live under `~/.plasticine/runtime/antidote`, so that storage is centralized without expanding Reconciliation ownership.
7. As an Owner, I want Plan and Apply to remain bounded to Tool Lock artifact URLs, so that Antidote does not cause Apply to clone arbitrary plugin repositories.
8. As an Owner, I want first shell startup to let Antidote generate or refresh its static bundle when needed, so that plugin cloning is a Tool-managed runtime effect rather than an Apply mutation.
9. As an Owner, I want repeated Apply runs after convergence to be no-ops unless the Antidote Tool Lock, plugin declaration, or Zsh bootstrap Desired State changes.
10. As an Owner, I want Doctor to validate the pinned Antidote payload and managed Zsh bootstrap while not enumerating or repairing Antidote-managed plugin state.
11. As an Owner, I want clean rollback or Tool Lock switches to remove old verified Antidote payloads only after a successful switch, while leaving plugin runtime state untouched.
12. As an Owner, I want clear documentation of the Antidote boundary, so that I know which files are Plasticine-managed and which files belong to Antidote.

## Implementation Decisions

- Antidote is a Managed Tool of the `shell` Component rather than a new public Component.
- Antidote uses a Tool Lock source archive artifact. The first implementation may repeat the same source archive for each Artifact Target rather than adding platform-independent Tool Lock entries.
- Managed Tool materialization gains directory payload support instead of special-casing Antidote in shell code.
- Directory payload ownership is recorded at a stable manifest or root path with a deterministic digest of extracted files, so Plan and Doctor can detect missing or drifted Antidote core files.
- A stable managed source shim under Plasticine Home points Zsh at the current versioned Antidote payload.
- The managed plugin declaration is Desired State. The generated static bundle and cloned plugins are Tool-managed State.
- Apply does not run `antidote bundle`, `antidote load`, `antidote update`, or any plugin clone operation.
- Zsh startup may run `antidote bundle` when the generated static bundle is older than the managed plugin declaration.

## Out of Scope

- Switching Plasticine's managed login shell from Zsh to Fish.
- Introducing a user-facing plugin API, profile system, or machine-local plugin override language.
- Managing Homebrew, Oh My Zsh, Prezto, Zinit, Sheldon, zplug, zcomet, zgen, or zgenom.
- Claiming SHA-256 verification for Zsh plugin repositories cloned by Antidote.
- Automatically running `antidote update` or changing plugin revisions outside a Release edit.
- Backing up, restoring, pruning, or drift-checking Antidote plugin clones, static bundles, snapshots, `.zcompdump`, or `.zwc` files.

## Testing Strategy

- Reconciler-level contract tests remain the primary seam.
- Directory Managed Tool tests cover raw cache verification, tar/zip extraction, required-entry validation, deterministic directory digesting, interrupted writes, version switching, old-payload cleanup, and Doctor drift reporting.
- Shell Component tests cover Antidote payload planning, managed plugin declaration materialization, Zsh bootstrap content, no-op second Apply, and one-shot `--component shell` behavior.
- Tool-managed State tests place files under `runtime/antidote` and prove Plan, Apply, Backup, Retirement, and Doctor do not inspect, modify, back up, or delete them.
- Release tests validate Tool Lock completeness for Antidote across all four Artifact Targets.

## Research

Primary-source research and shell/plugin-manager comparison are recorded in `docs/research/zsh-plugin-managers-and-shell-comparison.md`.

