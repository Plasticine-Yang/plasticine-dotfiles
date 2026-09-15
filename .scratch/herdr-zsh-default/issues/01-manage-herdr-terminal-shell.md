# 01: Manage Herdr's terminal shell policy

**Status:** done

Configure panes created by Herdr to start the target machine's Zsh directly,
without depending on the server's inherited `SHELL` environment variable.

- [x] Manage only `terminal.default_shell` and `terminal.shell_mode`.
- [x] Preserve unrelated Herdr settings and native runtime state.
- [x] Validate before apply, back up changed configuration, and preserve mode.
- [x] Reload a running server without terminating existing panes.
- [x] Verify convergence, idempotency, combined installation, and static checks.
- [x] Document the ownership boundary and new-pane behavior.

## Comments

Implemented with a chezmoi source modifier so Owner settings remain in place.
The rendered Zsh path is machine-local. A changed configuration creates a
reload marker; the post-apply step consumes it with `herdr server reload-config`
only when `herdr status server` reports a running server.
