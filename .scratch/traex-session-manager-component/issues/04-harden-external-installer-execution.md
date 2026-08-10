# 04 — Make external installer execution resilient and observable

**What to build:** Complete the external installer contract so the Owner can understand and control a mutable upstream operation, observe its progress, recover from failures, and trust that unrelated Reconciliation work continues.

**Blocked by:** 01 — Bootstrap a missing TSM installation.

**Status:** ready-for-agent

- [ ] Self-managed Tool installer URLs must be Release-declared HTTPS values and cannot be overridden by Workstation-local configuration.
- [ ] Apply downloads the script into a private temporary file and executes that file rather than piping network content directly into a shell.
- [ ] Installer execution inherits the Workstation's normal `HOME`, `PATH`, proxy settings, and ordinary process environment required by the upstream script.
- [ ] Installer stdout and stderr remain visible in CLI and TUI operation output without leaking sensitive URL credentials.
- [ ] Ctrl-C and context cancellation stop the active installer, preserve terminal restoration behavior, and return the established interrupted outcome.
- [ ] Installer download and execution are bounded to two minutes and cannot leave Reconciliation indefinitely blocked.
- [ ] Temporary installer content is cleaned after success, download failure, nonzero exit, post-install health failure, cancellation, and timeout.
- [ ] Download failure, script failure, timeout, cancellation, and failed post-install health are attributed to `traex-session-manager` with useful progress and next-action output.
- [ ] Plasticine does not guess at rollback of partial upstream effects; a later Plan reobserves the primary executable and a later Apply can retry.
- [ ] A TSM operational failure produces a partial result while unrelated Components continue and retain their successful durable effects.
- [ ] Local HTTP and command adapters test success and every failure mode without real external network access or remote code execution.
- [ ] CLI and TUI contract tests cover visible progress, failure, cancellation, risk rendering, and next actions without retesting private executor decomposition.
- [ ] User documentation explains the Self-managed Tool ownership boundary, explicit `tsm self-update`, ignored aliases and versions, ordinary authorization, and preservation on Scope exclusion or Component retirement.
- [ ] The complete release validation gate passes after all Self-managed TSM behavior is integrated.
