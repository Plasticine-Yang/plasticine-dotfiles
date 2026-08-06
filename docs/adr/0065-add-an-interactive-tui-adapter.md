# Add a full-screen interactive Adapter without changing Reconciliation policy

Running the Workstation CLI without a subcommand will open a full-screen TUI
when both input and output are usable terminals. The TUI is an interactive
Adapter over the concrete Reconciler Module: it may project Results, collect
session settings, authorize the exact immutable Apply Plan, observe progress,
and temporarily yield the controlling terminal, but it will not duplicate or
override Reconciliation policy.

The existing `plan`, `apply`, `doctor`, `upgrade`, and `version` commands retain
their human-readable text, options, color behavior, and exit statuses. A bare
command without a usable terminal, or with `TERM=dumb`, will print subcommand
guidance and return usage status 2 rather than emitting full-screen control
sequences. `NO_COLOR` disables TUI color but not the terminal control required
for the alternate screen.

The initial Dashboard performs no Plan, Reconciliation State read, mutation,
network access, or update check. Plan, Apply, and Doctor run only after explicit
Owner action, and self-upgrade remains the separate `upgrade` command. Session
results, progress, Workstation Scope drafts, and one-run Component filters are
not persisted as UI state; a Scope change becomes durable only through the
normal authorized Apply contract.
