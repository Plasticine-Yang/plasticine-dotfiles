# Triage Labels

The tracker uses the five canonical triage roles plus the repo-specific terminal state `done`.

| Role in mattpocock/skills | Status in our tracker | Meaning |
| ------------------------- | --------------------- | ------- |
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate the ticket |
| `needs-info` | `needs-info` | Waiting for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified and ready for an agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation |
| `wontfix` | `wontfix` | Will not be actioned |
| `done` | `done` | Implementation is complete, acceptance criteria are met, and relevant verification passes |

When a skill mentions a canonical role, use the corresponding status string from this table. Each implementation ticket has exactly one `Status:`. Preserve additional categories such as `bug` or `enhancement` separately from its state, and retain project-specific extra states.

Tickets normally move from `needs-triage` to `needs-info`, `ready-for-agent`, `ready-for-human`, or `wontfix`; after information is supplied, return to `needs-triage`. Completed implementation tickets move from an actionable state to `done`; completion notes, verification, commits, dependency unlocking, and pending-query exclusions follow `issue-tracker.md`.

Exclude `done` from pending-development queries. Reopen a completed ticket only at the user's explicit request or with evidence of a new defect. Wayfinder's research, prototype, and grilling states `claimed` / `resolved` retain their meaning; implementation tickets with `Type: task` finish as `done`.
