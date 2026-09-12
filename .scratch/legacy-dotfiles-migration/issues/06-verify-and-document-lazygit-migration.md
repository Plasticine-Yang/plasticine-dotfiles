# 06 — Verify and document the Lazygit migration

Status: ready-for-agent

Blocked by: 04, 05

## What to build

Close the Lazygit increment with interface-level runtime verification, route and composition regression coverage, and user documentation. Record Lazygit as complete without claiming migration of its native runtime state, automatic upgrades, PATH ownership, or legacy cleanup.

## Acceptance criteria

- A real-Zsh disposable-HOME test proves the exact `lg` alias invokes the selected healthy `lazygit` command and still allows later Owner `.zshrc` content to run and override earlier defaults.
- Runtime verification covers Lazygit-only and combined `shell` plus Lazygit composition. Existing blocks retain their locations, missing blocks use deterministic catalog order, and repeated application is byte-identical.
- Installer and integration tests cover empty selection; each single feature; `lazygit` combined pairwise with `shell` and `github-ssh`; all three together in different option orders; non-interactive requirements; preview; cancellation; dry runs; selected/unselected malformed markers; unsafe targets; partial tool failure; and satisfied reruns.
- Route tests prove the same official-release behavior on macOS and Linux across both supported architectures. Fixtures prove exact asset-name mapping, exact member extraction, checksum enforcement, atomic publication, and no network during preview.
- Isolation tests populate Lazygit configuration, cache/log data, repository-local state, an existing healthy arbitrary-version binary, and legacy paths, then prove unselected applies and satisfied reruns leave them byte-identical and unbacked-up.
- POSIX syntax and ShellCheck cover installer-side scripts and shared composition templates; Zsh syntax/runtime checks cover the alias result. Existing installer, shell, integration, and release suites remain green on the repository's Linux/macOS CI matrix.
- README documents `--lazygit`, combined non-interactive usage, the exact managed block, shared `.zshrc` backup/mode behavior, healthy-owner retention, the direct official-release route, checksum trust boundary, and failure/retry behavior. It states that missing-tool installation invokes no package manager or `sudo`.
- README makes the PATH seam explicit: the alias invokes `lazygit` by name; `shell` supplies the existing `~/.local/bin` default, while Lazygit-only selection does not change PATH and may require the Owner to expose `~/.local/bin`.
- README states that Plasticine does not manage Lazygit configuration/runtime state, upgrade or remove a healthy installation, remove `~/.plasticine-dotfiles`, or migrate/clean legacy state.
- The feature spec records the Lazygit increment as complete only after tickets 04–06 and all relevant verification pass; remaining legacy capabilities stay future work.

## Comments
