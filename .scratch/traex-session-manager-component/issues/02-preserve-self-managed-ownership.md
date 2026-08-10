# 02 — Preserve the Self-managed Tool ownership lifecycle

**What to build:** Make Plasticine consistently honor the handoff of TSM ownership: it may restore the minimum runnable capability, but it never owns, versions, adopts, drifts, backs up, retires, or over-diagnoses TSM-controlled content.

**Blocked by:** 01 — Bootstrap a missing TSM installation.

**Status:** ready-for-agent

- [ ] Any existing primary executable whose health command succeeds is accepted without adoption, conflict, backup, replacement, or version comparison.
- [ ] Replacing or self-updating a runnable TSM executable never creates drift, cleanup, downgrade, or a planned change.
- [ ] A missing, non-executable, or health-command-failing primary executable plans and retries the upstream installer on a later Apply.
- [ ] The long-name alias and any PATH-resolved executable outside the fixed primary location have no effect on Plan, Apply, or Doctor.
- [ ] TSM executable paths, versions, installer effects, and bootstrap history never enter Reconciliation State, Ownership, pending-work journals, Secret References, or migration data.
- [ ] Excluding the Component through Workstation Scope suppresses all TSM observation and bootstrap behavior while preserving existing tool-owned files.
- [ ] Re-enabling the Component observes the Workstation's current primary executable rather than relying on remembered installation history.
- [ ] Removing the Component from a later catalog does not produce Retirement, deletion, backup, or conflict for TSM-controlled paths.
- [ ] Doctor reports only whether the active primary executable can run; it ignores version freshness and aliases and emits no update advice.
- [ ] Reconciler contract tests verify the lifecycle through observable Results, state, and filesystem outcomes, including native replacement, Scope suspension, re-enablement, and catalog removal.
