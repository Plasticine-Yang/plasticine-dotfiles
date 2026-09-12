# 03 — Verify and document the shell migration

Status: done

Blocked by: 01, 02

## What to build

Close the Zsh increment with interface-level runtime verification, regression coverage, and user documentation. Record the shell capability as migrated without claiming cleanup or migration of any other legacy capability.

## Acceptance criteria

- Real-Zsh tests prove that the managed fragment loads the managed Antidote declaration and optional Owner declaration, initializes contributed completions, applies Powerlevel10k preferences, and returns control to later Owner `.zshrc` content.
- Missing or failing optional Antidote, plugin, completion, prompt, and fnm layers warn only in interactive shells and do not abort later Owner content.
- A failing `fnm env --shell zsh` result is not evaluated, and the feature does not install fnm or relocate its state.
- Generated Antidote bundles, plugin checkouts, caches, completion dumps, compiled files, and `~/.zsh_plugins.local.txt` are neither tracked, replaced, backed up, nor removed.
- Installer and integration tests cover empty selection, shell-only selection, GitHub-SSH-only selection, combined selection, non-interactive requirements, cancellation, dry reruns, and partial `chsh` failure.
- POSIX syntax checks cover installer-side scripts and Zsh syntax checks cover managed Zsh assets. Existing repository tests remain green.
- README documents `--shell`, combined non-interactive usage, managed paths, Owner extension points, native tool ownership, possible package-manager/credential effects, and `chsh` failure behavior.
- README states that this feature neither removes `~/.plasticine-dotfiles` nor migrates or cleans legacy runtime state.
- The feature spec records the Zsh increment as complete only after implementation and all relevant verification pass; all other legacy capabilities remain future work.

## Comments

Closed with runtime verification, regression coverage, and documentation. The only shipped-file change is a `# shellcheck shell=sh` directive in `.chezmoitemplates/shell-zshrc-block` (needed for the new POSIX syntax check to run on that extensionless template); the composed `.zshrc` block and every other installed artifact stay byte-identical, which `tests/integration.sh` asserts.

- `tests/shell-runtime.sh` (new) starts a real Zsh against the repository's actual artifacts in disposable HOMEs. It proves the managed fragment loads the managed declaration and the optional Owner declaration in that order, initializes completions contributed through the declaration (`kind:fpath` stand-in plus `compinit`, asserted both as `_comps` registration and as an autoloadable completion), applies the managed Powerlevel10k preferences from the managed path, and returns control to later Owner `.zshrc` content that can override the shared defaults.
- The suite pins the platform route instead of accepting either one: Antidote is installed on the host's native route (Homebrew prefix on macOS, `~/.antidote` on Linux) and a poisoned stand-in is left on the other route, so a fragment that resolves the wrong route fails the run.
- Every optional layer is exercised in its missing and failing forms — Antidote, managed declaration, Owner declaration, completion initialization, Powerlevel10k preferences, `fnm` activation — in both interactive and non-interactive shells: warnings appear only in interactive shells and later Owner content always runs. A failing `fnm env --shell zsh` result is not evaluated, no other `fnm` subcommand runs, and existing fnm state is byte-identical afterwards; a succeeding `fnm env` is evaluated, so the failing case is observed against a working baseline. A broken managed fragment is contained by the `.zshrc` block itself.
- Reading is the only thing the fragment may do to Antidote state: a runtime scenario pre-populates generated bundles, a plugin checkout, caches, `*.zwc` compiled files and `~/.zsh_plugins.local.txt`, proves they are byte-identical, proves no directory appears anywhere under the disposable HOME, and proves the only plasticine-owned file remains the managed fragment.
- macOS-only `fnm` behaviour is covered too: when `fnm` is missing from `PATH` but present in the Homebrew prefix, the fragment exposes that prefix's executable directory and activates the existing `fnm` without moving any state. `README.md` documents this.
- `tests/shell.sh` adds installer-level isolation (tool-owned state survives applies and reruns byte-for-byte, is never backed up, and is not managed by chezmoi) and states the partial-`chsh` case explicitly: the configuration is applied and usable while the transition is denied, and a later rerun retries only the transition. The same suite also covers an unobserved `chsh` success and a terminal-less `chsh`.
- `tests/installer.sh` cancellation now asserts that every shell target (`.zshrc`, `.zsh_plugins.txt`, `.p10k.zsh`, `.plasticine`) and both SSH artifacts are absent after declining the confirmation. Interactive cancellation needs `expect`; the suite now says so when it skips that check instead of passing silently.
- `tests/integration.sh` adds the preview before mutation, an empty preview plus an unchanged destination for a satisfied dry rerun, and a successful combined `github-ssh` + `shell` apply that keeps both features' outputs intact. It also now runs POSIX syntax checks over installer-side scripts (including the shared `.zshrc` block composer and the test suites) and keeps the Zsh syntax checks over the managed Zsh assets.
- Interpretation recorded for review: `fnm` absence stays silent. This feature never installs `fnm`, so only a failing *activation* is a degraded layer; warning on every interactive shell for a user without `fnm` would be noise the spec explicitly avoids ("guarded activation for an already installed `fnm`").
- README documents `--shell`, combined non-interactive usage, managed paths and the marker block, Owner extension points, native tool ownership, package-manager and credential effects, `chsh` failure behavior, what cancelling does and does not leave behind, and that the feature neither removes `~/.plasticine-dotfiles` nor migrates or cleans legacy runtime state. `spec.md` records the Zsh increment as complete; every other legacy capability remains future work.
- Falsification: every new claim was re-run against a deliberate breakage and each break was caught — evaluating failing `fnm` output, warning in non-interactive shells, skipping the Owner declaration, skipping `compinit`, skipping Powerlevel10k preferences, aborting later Owner content, resolving the wrong Antidote route, creating a plasticine-owned cache directory, dropping the Homebrew `fnm` exposure, having chezmoi manage a completion dump, backing up tool-owned state, and applying despite a declined confirmation.
