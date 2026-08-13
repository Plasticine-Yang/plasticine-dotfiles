# 04 — Make external installer execution resilient and observable

**What to build:** Complete the external installer contract so the Owner can understand and control a mutable upstream operation, observe its progress, recover from failures, and trust that unrelated Reconciliation work continues.

**Blocked by:** 01 — Bootstrap a missing TSM installation.

**Status:** ready-for-human

- [x] Self-managed Tool installer URLs must be Release-declared HTTPS values and cannot be overridden by Workstation-local configuration.
- [x] Apply downloads the script into a private temporary file and executes that file rather than piping network content directly into a shell.
- [x] Installer execution inherits the Workstation's normal `HOME`, `PATH`, proxy settings, and ordinary process environment required by the upstream script.
- [x] Installer stdout and stderr remain visible in CLI and TUI operation output without leaking sensitive URL credentials.
- [x] Ctrl-C and context cancellation stop the active installer, preserve terminal restoration behavior, and return the established interrupted outcome.
- [x] Installer download and execution are bounded to two minutes and cannot leave Reconciliation indefinitely blocked.
- [x] Temporary installer content is cleaned after success, download failure, nonzero exit, post-install health failure, cancellation, and timeout.
- [x] Download failure, script failure, timeout, cancellation, and failed post-install health are attributed to `traex-session-manager` with useful progress and next-action output.
- [x] Plasticine does not guess at rollback of partial upstream effects; a later Plan reobserves the primary executable and a later Apply can retry.
- [x] A TSM operational failure produces a partial result while unrelated Components continue and retain their successful durable effects.
- [x] Local HTTP and command adapters test success and every failure mode without real external network access or remote code execution.
- [x] CLI and TUI contract tests cover visible progress, failure, cancellation, risk rendering, and next actions without retesting private executor decomposition.
- [x] User documentation explains the Self-managed Tool ownership boundary, explicit `tsm self-update`, ignored aliases and versions, ordinary authorization, and preservation on Scope exclusion or Component retirement.
- [x] The complete release validation gate passes after all Self-managed TSM behavior is integrated.

## Comments

- Verified by deterministic success, download failure, script failure, post-health failure, cancellation, timeout, cleanup, retry, CLI, and TUI tests.
- `scripts/validate-release.sh` passes with the native smoke explicitly excluding TSM so validation never executes the real upstream installer.
