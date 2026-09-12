# 03 — Verify and document the shell migration

Status: ready-for-agent

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
