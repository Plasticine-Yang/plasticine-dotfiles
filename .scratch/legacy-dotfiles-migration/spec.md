# Incrementally migrate legacy dotfiles capabilities

Status: ready-for-agent

## Problem

The legacy repository at `~/.plasticine-dotfiles` contains useful workstation capabilities that are not yet available in this chezmoi-based repository. Migrating every capability in one change would couple unrelated tools, make failures hard to isolate, and make it difficult to verify that the new implementation preserves the intended behavior without also preserving the legacy architecture.

The migration therefore needs a durable place to record scope and progress while allowing each capability to ship independently. The first requested capability is the Zsh environment.

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

## Current increment: `shell`

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

The shared Zsh fragment may contain guarded activation for an already installed `fnm`, because this preserves the existing shell experience. Installing or updating `fnm` is not part of the current increment. Lazygit and Zellij aliases likewise remain owned by their future independent migrations.

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

## Out of scope for this increment

- Installing or updating fnm, Lazygit, Zellij, Neovim, uv, TraeX, or other legacy capabilities.
- Migrating generated `.zsh_plugins.zsh` files, Antidote plugin checkouts, caches, or completion state.
- Recreating the legacy Plasticine CLI, its callback graph, package batching framework, source layout, or release architecture.
- Removing `~/.plasticine-dotfiles` or any legacy-managed resource.
- Automatically resolving malformed existing managed blocks or replacing non-regular targets.

## Delivery plan

1. Migrate shell selection, configuration assets, and safe `.zshrc` composition for workstations that already have healthy Zsh and Antidote.
2. Add missing-tool bootstrap and the final login-shell transition without changing the configuration ownership seam.
3. Complete combination, runtime, isolation, rerun, and documentation verification.

Future capability migrations add new tickets to this directory after their scope is agreed.

## Completion criteria for the current increment

- Interactive selection and `-y --shell` both select exactly the `shell` feature.
- `shell` and `github-ssh` can be selected together without either feature overwriting the other's selection data or configuration.
- A fresh supported workstation reaches a usable Zsh, Antidote, Powerlevel10k, and managed configuration state.
- An existing workstation preserves Owner-controlled `.zshrc` content, local plugin declarations, healthy native installation owners, and all tool-managed runtime state.
- Preview precedes mutation, reruns converge without unnecessary writes, and unselected shell state is not inspected.
- Focused disposable-HOME tests and the existing installer/integration suites pass.
- README documents interactive selection, automated selection, ownership, runtime state, and the non-migration of legacy cleanup.
