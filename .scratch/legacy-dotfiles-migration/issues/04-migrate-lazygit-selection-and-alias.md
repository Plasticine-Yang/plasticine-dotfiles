# 04 — Migrate Lazygit selection and alias composition

Status: done

## What to build

Add `lazygit` to the current installer's explicit selection interface and reproduce the accepted alias on a workstation where Lazygit is already healthy. Deepen the current shell-only `.zshrc` composer into a shared Integration Block module so each selected feature declares its block while parsing, validation, byte-preserving composition, backup, and mode handling remain local to one implementation.

Missing-tool installation belongs to ticket 05. This ticket must fail with guidance when selected Lazygit is missing or unhealthy.

## Acceptance criteria

- Interactive selection includes `lazygit`, remains initially empty, and can combine it with `shell` and `github-ssh`. Non-interactive installation accepts `-y --lazygit`; `--lazygit` without `-y` follows the existing tool-option rule.
- The allowed-tool set, persisted sorted selection, usage text, ignore rules, and source targeting include Lazygit without changing the meaning of existing selections. Option order and duplicate internal selection values do not change the result; unknown values still fail before apply.
- Leaving Lazygit unselected performs no Lazygit health/platform probe and does not inspect its marker namespace. Lazygit-only selection performs no Zsh, Antidote, Powerlevel10k, login-shell, or shell-owned-file probe.
- A selected existing Lazygit must resolve to an executable that passes `lazygit --version`. Any healthy version and installation path is accepted without migration or reinstall. A present but unhealthy executable is left untouched and receives repair guidance.
- The only Lazygit configuration target is the independently marked block in Owner-controlled `~/.zshrc`, with exact body `alias lg='lazygit'`. The feature does not create or manage a whole Lazygit configuration file.
- One shared Integration Block module composes all selected `.zshrc` declarations. Its interface hides marker scanning, final candidate generation, backup, and mode coordination from feature callers; the source modifier and pre-apply validation use the same implementation.
- Every selected marker namespace is validated before any selected tool effect. Duplicate, nested, reversed, incomplete, CRLF-damaged, or otherwise malformed selected markers fail without mutation. Unselected namespaces, including malformed ones, remain opaque.
- A missing selected block is inserted at the beginning in deterministic catalog order. A valid existing selected block is replaced in place without moving other blocks. Selecting `shell` and `lazygit` never duplicates or globally reorders their blocks.
- Every byte outside selected blocks is preserved, including NUL/non-UTF-8 bytes, CRLF content, missing final newline, and multiple trailing newlines. `.zshrc` symlinks, directories, FIFOs, and other non-regular targets are rejected.
- One changed `.zshrc` produces one private `0600` full-file backup under a `0700` Plasticine backup directory for the apply, including when two selected blocks change. Existing mode is restored after apply. Historical shell backups are not moved or deleted.
- Preview and the existing final confirmation cover the alias change. Cancellation changes no destination file or tool. Repeating a satisfied installation creates no rewrite, backup, mode change, or tool action.
- Disposable-HOME tests cover empty, Lazygit-only, shell-only, GitHub-SSH-only, pairwise and three-feature selection; selected/unselected malformed markers; arbitrary outside bytes; unsafe targets; cancellation; option-order independence; and rerun convergence. Existing shell behavior and tests remain green after the composer is deepened.

## Source references

- Legacy feature behavior: `~/.plasticine-dotfiles/lib/plasticine/features/lazygit.sh` at commit `3deacd68d5f289be778a7ac4bf3e575fb9905bd7`
- Legacy Integration Block contract and coverage: `lib/plasticine/blocks.sh` and `tests/portable/lazygit_test.sh` at the same commit
- Current composition seam: `.chezmoitemplates/shell-zshrc-block`, `modify_dot_zshrc.tmpl`, and the shell configuration scripts in this repository

## Comments
