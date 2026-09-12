# 01 — Migrate shell selection and configuration

Status: ready-for-agent

## What to build

Add `shell` to the current installer's explicit selection interface and reproduce the accepted Zsh configuration on a workstation where Zsh and Antidote are already healthy. Keep chezmoi responsible for declared whole files and use a source modifier for the independently marked block in the Owner-controlled `.zshrc`.

## Acceptance criteria

- Interactive selection includes `shell`, remains initially empty, and supports selecting it together with `github-ssh`.
- Non-interactive installation accepts `-y --shell`; `--shell` without `-y` follows the existing rule for tool options.
- The selected-tool representation supports an unordered set rather than a single hard-coded value; unknown values fail before apply.
- Leaving `shell` unselected excludes every shell-owned source target and performs no Zsh or Antidote health probe.
- Selecting `shell` requires a healthy existing Zsh and Antidote, with actionable errors for missing or unhealthy prerequisites. Missing-tool installation belongs to ticket 02.
- Chezmoi manages exactly `~/.plasticine/zsh/shared.zsh`, `~/.zsh_plugins.txt`, and `~/.p10k.zsh` for `shell`.
- The migrated assets preserve the legacy plugin set, vi-mode preferences, completion initialization, Powerlevel10k preferences, `~/.local/bin` PATH setup, optional `~/.zsh_plugins.local.txt`, and guarded `fnm env --shell zsh` activation.
- A `.zshrc` source modifier maintains at most one `# >>> Plasticine shell >>>` block, inserting a missing block at the beginning and replacing a valid existing block in place.
- Every byte outside the selected block is preserved. Duplicate, nested, reversed, or incomplete selected markers fail before mutation.
- `.zshrc` and the three whole-file targets reject symlinks, directories, FIFOs, and other non-regular targets. Existing file modes are preserved.
- The existing preview and final confirmation cover the configuration changes; a cancelled invocation changes nothing.
- Repeating an already satisfied install produces no new content changes or backups.
- Disposable-HOME tests cover selection, exclusion, combined `shell` plus `github-ssh`, byte preservation, malformed markers, unsafe targets, cancellation, and rerun behavior.

## Source references

- Legacy behavior: `~/.plasticine-dotfiles/lib/plasticine/features/shell.sh` at commit `3deacd68d5f289be778a7ac4bf3e575fb9905bd7`
- Assets: `home/dot_plasticine/zsh/shared.zsh`, `home/dot_zsh_plugins.txt`, and `home/dot_p10k.zsh` at the same commit
- Existing composition precedent: `private_dot_ssh/modify_private_config` in this repository

## Comments
