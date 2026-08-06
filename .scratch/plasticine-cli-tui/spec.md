# Plasticine Interactive TUI

Status: implemented

## Problem Statement

Plasticine's grouped text output is stable and script-friendly, but the Owner
must still coordinate Plan review, Workstation Scope changes, one-run Component
filters, risk authorization, Apply progress, and Doctor diagnostics through
separate invocations and flags. The Workstation CLI needs a polished interactive
Adapter without weakening Reconciliation policy or destabilizing existing
commands.

## Solution

Running `plasticine` with an interactive terminal opens a full-screen Bubble Tea
Dashboard. It starts without reading Reconciliation State, planning, mutating,
or using the network. The Owner explicitly starts Plan, Apply, or Doctor and can
review one session's latest results across Dashboard, Plan, Components, and
Doctor screens.

The TUI is an Adapter over the concrete Reconciler Module. Apply calls
`Reconciler.Apply` once; its authorization callback presents the exact immutable
Plan that Apply will execute and returns a structured decision for ordinary
mutation, System Changes, adoption, and Retirements. Progress events are
observation-only. Commands requiring the controlling terminal temporarily
suspend the full-screen renderer and resume it after completion.

Existing `plan`, `apply`, `doctor`, `upgrade`, and `version` invocations retain
their text output, options, color policy, and exit status contract. A bare
command without a usable terminal prints guidance and exits with usage status
2. No JSON, RPC, persistent UI cache, or self-upgrade screen is introduced.

## User Stories

1. As the Owner, I can open a modern Dashboard and decide when any operation
   starts.
2. As the Owner, I can review Plan risks, changes, Retirements, checks, and next
   actions without losing Component context.
3. As the Owner, I can draft a persistent Workstation Scope separately from a
   one-run Component filter.
4. As the Owner, I can authorize only the risk classes shown in the exact Apply
   Plan.
5. As the Owner, I can follow Apply progress without treating UI events as the
   authoritative outcome.
6. As the Owner, I can run Doctor and see unhealthy checks before healthy ones,
   grouped by Support, Managed Resources, Network, and GitHub SSH.
7. As a script author, I can keep using the existing subcommands unchanged.

## Interaction Contract

- Screens: Dashboard, Plan, Components, Doctor.
- Global keys: `1`-`4`, `p`, `a`, `d`, `?`, and `q`.
- Lists: arrows, `j`/`k`, `Tab`, `Enter`, `Space`, and mouse wheel.
- Width at least 100 uses a two-column result layout; widths 60-99 use one
  column with focus/detail switching; dimensions below 60x18 show a resize
  prompt.
- The theme uses a neutral dark surface with cyan and violet accents. `NO_COLOR`
  removes color but preserves alternate-screen terminal control.
- Scope edits are session drafts and persist only through an authorized Apply.
  Dirty drafts require discard confirmation on normal exit.
- One-run Component filters, adoption intent, and skip-login-shell are Run
  Settings and never become Workstation Scope.
- Missing GitHub SSH Secret References may prompt for a private-key path. The
  path may be displayed; private-key contents must never enter the TUI.
- `q` is disabled while an operation is active. Ctrl-C requests cancellation,
  waits for the operation to return safely, restores the terminal, and exits
  130.

## Implementation Decisions

- Use Go 1.26.5, Bubble Tea 1.3.10, Bubbles 1.0.0, Lip Gloss 1.1.0, and
  creack/pty 1.1.24 for tests only.
- Extract a pure Result projection shared by text and TUI renderers.
- Extract one Workstation runtime Module that constructs the concrete
  Reconciler and base Request for both command Adapters.
- Keep the TUI Module's external interface small: one run function receiving a
  context, Runtime, and terminal IO.
- Expose a read-only Reconciler Component catalog with stable IDs and
  dependencies while keeping display copy in the TUI.
- Use structured authorization, redacted progress events, and a terminal-command
  runner seam inside Reconciliation rather than duplicating policy in the TUI.

## Out Of Scope

- Running `upgrade` from the TUI.
- Persisting session results, filters, logs, or UI preferences.
- Changing Desired State, Conflict, Retirement, Scope, System Change, or Secret
  Reference semantics.
- Adding a machine-readable output contract or user-editable configuration
  schema.

## Acceptance

- Bare command PTY smoke tests open Dashboard without Plan, network, or mutation
  and restore the terminal for `q` and Ctrl-C.
- Apply executes the same immutable Plan presented to structured authorization;
  missing any required risk decision causes zero mutation.
- Scope drafts and one-run filters remain distinct in requests and UI.
- Progress covers operation, Component, and Change lifecycle without Secret
  content.
- Existing text command contract tests remain green.
- `go test ./...`, `go vet ./...`, `git diff --check`, and
  `scripts/validate-release.sh` pass, including four CGO-disabled Artifact
  Targets.
