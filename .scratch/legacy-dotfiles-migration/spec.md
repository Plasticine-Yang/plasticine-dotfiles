# Incrementally migrate legacy dotfiles capabilities

Status: ready-for-agent

## Problem

The legacy repository at `~/.plasticine-dotfiles` contains useful workstation capabilities that are not yet available in this chezmoi-based repository. Migrating every capability in one change would couple unrelated tools, make failures hard to isolate, and make it difficult to verify that the new implementation preserves the intended behavior without also preserving the legacy architecture.

The migration therefore needs a durable place to record scope and progress while allowing each capability to ship independently. The Zsh environment shipped first; Lazygit is the current increment.

## Source baseline

Behavior is inventoried from legacy commit `3deacd68d5f289be778a7ac4bf3e575fb9905bd7`. The commit is evidence for the intended behavior, not an implementation dependency: the new repository must not read or execute files from `~/.plasticine-dotfiles` during installation.

Migration is defined by user-visible behavior and safety properties rather than file-for-file copying. The current repository's `install.sh` and chezmoi interfaces remain authoritative.

## Migration model

- This tracker feature owns the incremental migration roadmap; it is not a selectable runtime feature.
- Each migrated capability becomes an independently selectable tool or feature in the current installer.
- A capability is complete only when installation, configuration, rerun behavior, isolation, tests, and documentation have migrated.
- A later capability may reuse a seam introduced by an earlier one, but this effort will not recreate the legacy CLI framework in advance.
- Existing healthy native installations remain with their current installation owners unless a capability specification explicitly says otherwise.
- Legacy repositories, managed files, runtime data, caches, backups, and login-shell choices are not automatically removed. Cleanup requires a separate, explicit migration design.

## Completed increment: `shell`

The first runtime feature is `shell`, selected interactively or with `install.sh -y --shell`. It covers one end-to-end Zsh experience:

- prepare a usable Zsh installation on supported macOS and Linux hosts;
- prepare Antidote through its reviewed native installation route;
- obtain Powerlevel10k through Antidote's plugin mechanism;
- manage `~/.plasticine/zsh/shared.zsh`, `~/.zsh_plugins.txt`, and `~/.p10k.zsh`;
- maintain only the `shell` Integration Block inside the Owner-controlled `~/.zshrc`;
- preserve optional Owner plugins in `~/.zsh_plugins.local.txt` and all `.zshrc` bytes outside the selected block;
- attempt a native login-shell transition only after usable configuration has been applied.

The `shell` feature keeps the legacy marker spelling so existing installations can be adopted in place without creating a duplicate block:

```zsh
# >>> Plasticine shell >>>
if [ -r "$HOME/.plasticine/zsh/shared.zsh" ]; then
    if ! . "$HOME/.plasticine/zsh/shared.zsh"; then
        if [[ -o interactive ]]; then
            print -ru2 -- "plasticine: shared shell configuration unavailable"
        fi
    fi
fi
# <<< Plasticine shell <<<
```

## Ownership and runtime boundaries

Chezmoi owns only the three declared whole-file targets. A source modifier owns only the marked `shell` block in `.zshrc`; `.zshrc` as a whole remains Owner-controlled. Existing regular files are previewed and backed up before replacement, existing modes are preserved, and non-regular targets are rejected. Repeating a satisfied installation produces no unnecessary changes or backups.

Antidote owns its checkout, generated bundles, plugin clones, caches, snapshots, completion dumps, and compiled files. Plasticine neither imports this state from the legacy repository nor manages or deletes it. `~/.zsh_plugins.local.txt` also remains Owner-controlled.

The shared Zsh fragment may contain guarded activation for an already installed `fnm`, because this preserves the existing shell experience. Installing or updating `fnm` was not part of the shell increment. Lazygit remained independently owned and is now scoped as the current increment below; the Zellij alias remains future work.

## Installation behavior

- macOS uses the healthy system Zsh. Antidote uses an existing healthy installation or the Homebrew route.
- Supported Debian/Ubuntu hosts use an existing healthy Zsh or the reviewed APT route. Antidote uses an existing healthy checkout or its official Git checkout route.
- Powerlevel10k is obtained through Antidote rather than copied or pinned by this repository.
- Existing healthy installations are accepted without version migration. Existing but unhealthy installations fail with repair guidance and are not overwritten through a fallback route.
- Configuration is applied only after required tools are healthy.
- Any required privilege, network operation, package-manager mutation, or `chsh` attempt is shown before the user's existing final confirmation.
- `--yes` skips the Plasticine confirmation only; it does not provide native credentials or synthesize input for another installer.
- `chsh` is attempted last. Failure retains the usable tools and configuration and returns a failure that can be retried.
- Leaving `shell` unselected must avoid shell-specific probes and mutations.

## Out of scope for the shell increment

- Installing or updating fnm, Lazygit, Zellij, Neovim, uv, TraeX, or other legacy capabilities.
- Migrating generated `.zsh_plugins.zsh` files, Antidote plugin checkouts, caches, or completion state.
- Recreating the legacy Plasticine CLI, its callback graph, package batching framework, source layout, or release architecture.
- Removing `~/.plasticine-dotfiles` or any legacy-managed resource.
- Automatically resolving malformed existing managed blocks or replacing non-regular targets.

## Shell delivery plan

1. Migrate shell selection, configuration assets, and safe `.zshrc` composition for workstations that already have healthy Zsh and Antidote.
2. Add missing-tool bootstrap and the final login-shell transition without changing the configuration ownership seam.
3. Complete combination, runtime, isolation, rerun, and documentation verification.

Future capability migrations add new tickets to this directory after their scope is agreed.

## Shell progress

The `shell` increment is complete: tickets 01, 02, and 03 are `done`, and every completion criterion below is covered by the repository's test suites and documentation.

- Verification lives in `tests/shell.sh` (installer-side selection, tool preparation, login-shell transition, runtime-state isolation, rerun convergence), `tests/shell-runtime.sh` (real-Zsh runtime behavior of the managed fragment in a disposable HOME), `tests/installer.sh`, and `tests/integration.sh` (composition, dry runs, non-interactive requirements, cancellation, syntax checks). `tests/shell-runtime.sh` and `tests/shell.sh` require a real `zsh`.
- Runtime reports: successful shells reach a usable Zsh, Antidote, Powerlevel10k, and the managed configuration; every optional layer (Antidote, managed declaration, Owner declaration, completions, Powerlevel10k preferences, `fnm` activation) degrades to an interactive-only warning without aborting later Owner `.zshrc` content.
- `fnm` is only activated, never installed, updated or relocated; a failing `fnm env --shell zsh` is not evaluated.
- Antidote-owned runtime state (bundles, plugin checkouts, caches, completion dumps, compiled files) and `~/.zsh_plugins.local.txt` are neither tracked, replaced, backed up, nor removed.

At shell closeout, everything else in "Out of scope for the shell increment" remained future work. Lazygit is now scoped below; removing `~/.plasticine-dotfiles` or any legacy-managed resource still requires a separate explicit migration design.

## Shell completion criteria

- Interactive selection and `-y --shell` both select exactly the `shell` feature.
- `shell` and `github-ssh` can be selected together without either feature overwriting the other's selection data or configuration.
- A fresh supported workstation reaches a usable Zsh, Antidote, Powerlevel10k, and managed configuration state.
- An existing workstation preserves Owner-controlled `.zshrc` content, local plugin declarations, healthy native installation owners, and all tool-managed runtime state.
- Preview precedes mutation, reruns converge without unnecessary writes, and unselected shell state is not inspected.
- Focused disposable-HOME tests and the existing installer/integration suites pass.
- README documents interactive selection, automated selection, ownership, runtime state, and the non-migration of legacy cleanup.

## Current increment: `lazygit`

The next runtime feature is `lazygit`, selected interactively or with `install.sh -y --lazygit`. It covers one independently selectable command-line experience:

- accept an existing healthy Lazygit without changing its version or installation owner;
- prepare a missing Lazygit directly from its official GitHub Release without invoking a package manager;
- maintain only the `lazygit` Integration Block inside the Owner-controlled `~/.zshrc`;
- preserve every `.zshrc` byte outside selected Integration Blocks and compose safely with the completed `shell` feature;
- leave Lazygit configuration, cache, repository state, and other runtime data outside Plasticine ownership.

The migrated alias retains the legacy marker spelling and body so an existing valid block is adopted in place:

```zsh
# >>> Plasticine lazygit >>>
alias lg='lazygit'
# <<< Plasticine lazygit <<<
```

### Ownership and composition boundaries

`~/.zshrc` remains Owner-controlled. A shared Integration Block module owns only the selected `shell` and `lazygit` blocks behind one composition interface. It validates every selected marker namespace before any selected tool mutation, ignores unselected namespaces, inserts missing selected blocks at the beginning in deterministic catalog order, replaces valid existing selected blocks in place, and never normalizes the order of existing blocks.

The shared module also owns `.zshrc` backup and mode coordination. One changed `.zshrc` produces one private full-file backup for the apply even when multiple selected blocks change; existing file mode is restored after apply. Historical backups remain untouched. Shell-owned whole-file backups remain under the shell feature. Non-regular `.zshrc` targets are rejected, and a satisfied rerun creates no rewrite or backup.

An existing healthy Lazygit remains owned by whatever installed it, including an existing Homebrew or APT copy. When Lazygit is missing, Plasticine publishes a checksum-verified official release executable at `~/.local/bin/lazygit` on both macOS and Linux; a later healthy rerun leaves it byte-identical and this increment adds no automatic update or removal policy. The executable is not a chezmoi-managed file.

The feature does not manage Lazygit's native configuration or runtime state, including `~/.config/lazygit`, caches, logs, and repository-local state. The alias deliberately invokes `lazygit` by name. PATH ownership remains independent: selecting `shell` supplies the existing `~/.local/bin` default, while a Lazygit-only Owner must already expose the installation route's executable directory or follow the documented route guidance.

### Installation behavior

- Darwin and Linux on `x86_64`/`amd64` and `arm64`/`aarch64` use the official Lazygit release assets. Host OS and architecture names are mapped to the asset's lowercase `darwin`/`linux` and `x86_64`/`arm64` spellings.
- A discovered executable must pass `lazygit --version`. A present but unhealthy executable is left untouched and fails with repair guidance; no fallback owner is attempted.
- Lazygit does not publish an official installer script. Its README publishes binary releases and a Linux command recipe; Plasticine implements the reviewed download steps itself rather than executing an opaque third-party installer or copying the recipe's privileged `/usr/local/bin` destination.
- The release route resolves `latest` only during apply, validates the returned tag, downloads the matching archive and same-release `checksums.txt`, verifies SHA-256, extracts only the `lazygit` member, health-checks it, and atomically publishes mode `0755` to `~/.local/bin/lazygit`. Preview performs no version lookup or network access.
- The release checksum is integrity evidence from the same GitHub Release trust boundary, not an independent signature. HTTPS and the published release boundary remain the authenticity basis.
- The route is planned and previewed before the existing final confirmation, including commands, network access, destination, checksum verification, and the alias change. Lazygit installation needs no package manager, `sudo`, native credentials, or terminal prompt.
- All selected configuration targets and marker namespaces are validated before the first tool mutation. All selected tools are prepared and rechecked before configuration backup, mode normalization, or apply. A failed download receives no alias; independently successful tool installation may remain and a rerun resumes from observed health.
- Leaving `lazygit` unselected avoids Lazygit health, platform, route, marker, configuration-state, and runtime-state inspection. Selecting Lazygit alone does not probe or prepare Zsh, Antidote, Powerlevel10k, `chsh`, or shell-owned files.

### Out of scope for the Lazygit increment

- Pinning a central Lazygit version, upgrading or replacing any healthy Lazygit, or adding an automatic update/removal policy.
- Managing or migrating Lazygit configuration, custom commands, caches, logs, repository state, or other runtime data.
- Installing Zsh or requiring the `shell` feature; changing Owner PATH configuration for Lazygit-only selection.
- Installing Lazygit through Homebrew, APT, another package manager, `go install`, or third-party wrappers such as `gah`. Existing healthy copies from those owners are still accepted.
- Recreating the legacy callback graph, package batching framework, tool lock, or versioned tool directories.
- Removing the legacy repository, its alias block, its installed binary, or any other legacy-managed resource outside the selected block adoption behavior.

### Lazygit delivery plan

1. Add selection, healthy-tool acceptance, and the exact alias while deepening the current shell-only composer into one selected-Integration-Block module for `.zshrc`.
2. Add the reviewed direct-release installation route, post-install health gates, and failure-safe ordering before configuration effects.
3. Complete runtime, combination, isolation, route, rerun, regression, and documentation verification.

### Lazygit completion criteria

- Interactive selection and `-y --lazygit` both select exactly the Lazygit feature, and it composes with `shell` and `github-ssh` in any option order.
- A healthy existing tool receives only the exact alias block; a fresh reviewed host reaches a healthy tool through the selected route before the alias is applied.
- Selected `.zshrc` blocks compose through one interface with byte preservation, selected-only validation, one backup per changed file, mode preservation, and convergent reruns.
- Missing, unhealthy, unsupported, malformed-release, checksum-failing, download-failing, extraction-failing, publication-failing, and post-install-health-failing states have deterministic errors and no fallback; configuration remains unchanged on tool failure.
- Unselected Lazygit state is not observed, Lazygit-only selection does not observe shell state, and malformed unselected block namespaces remain opaque.
- Disposable-HOME tests use controlled network, release metadata, checksum, archive, platform, filesystem, and health fixtures; no test mutates the developer's machine or uses the network.
- A real-Zsh runtime check proves `lg` invokes `lazygit`, while installer and integration suites cover selection, preview, cancellation, composition, partial failure, and rerun behavior.
- README documents selection, the direct-release route, PATH responsibility, managed block and backup behavior, native installation ownership, unmanaged runtime state, and the absence of legacy cleanup or healthy-version migration.
