# Triage Labels

The tracker uses the five canonical triage roles plus the repo-specific terminal state `done`.

| Role in mattpocock/skills | Status in our tracker | Meaning |
| ------------------------- | --------------------- | ------- |
| `needs-triage` | `needs-triage` | Maintainer needs to evaluate the ticket |
| `needs-info` | `needs-info` | Waiting for more information |
| `ready-for-agent` | `ready-for-agent` | Fully specified and ready for an agent |
| `ready-for-human` | `ready-for-human` | Requires human implementation |
| `wontfix` | `wontfix` | Will not be actioned |
| `done` | `done` | Implementation and relevant verification are complete |

When a skill mentions a canonical role, use the corresponding status string from this table. A ticket carries exactly one state. When development and relevant verification finish, replace its current state with `done`.
