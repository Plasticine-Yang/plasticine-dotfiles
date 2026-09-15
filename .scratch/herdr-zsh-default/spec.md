# Herdr panes default to Zsh

The Herdr server can start without a `SHELL` environment variable. Herdr 0.9.0
then falls back to `/bin/sh`, even when the account and interactive environment
normally use Zsh. Running `zsh` inside a pane only replaces that pane's shell
and does not fix subsequent panes.

This follow-up requirement supersedes the earlier blanket exclusion of Herdr
configuration from Base Dotfiles management. The `herdr` Feature owns only
`terminal.default_shell` and `terminal.shell_mode` in
`~/.config/herdr/config.toml`. Every other Herdr setting and all native runtime
state remain Owner-managed.

## Required behavior

- Resolve the target machine's absolute Zsh path and set it as
  `terminal.default_shell`; fail when a healthy executable is unavailable.
- Set `terminal.shell_mode` to `non_login` so interactive panes load `.zshrc`
  without repeating login-shell initialization.
- Preserve unrelated TOML content and the existing file mode. Back up a changed
  existing file under `~/.plasticine/backups/herdr/`.
- Validate the candidate with `herdr config check` before applying it.
- If the server is running, reload its configuration after a change without
  stopping the server or existing panes. Only newly created panes must change.
- Keep repeated applies idempotent and do not create redundant backups or
  reloads.

## Verification

Exercise missing and existing configuration through the installer/chezmoi
entrypoint with controlled Herdr fixtures. Verify preservation, exact Zsh path,
non-login mode, backup and mode handling, idempotency, and live reload. Keep the
integration, combined-installation, workflow, CI-gate, ShellCheck, and diff
checks green.
