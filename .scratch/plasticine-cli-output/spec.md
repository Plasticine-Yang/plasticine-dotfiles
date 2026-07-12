# Plasticine CLI Human-Readable Output

Status: ready-for-agent

## Problem Statement

The current `plasticine plan`, `apply`, and `doctor` output is a flat stream of text lines. It is useful for contract tests, but tiring for a human running the CLI on a real Workstation: the Owner must scan many repeated lines to answer basic questions such as which Components will change, which paths are risky, why the command failed, and which flag or command should be used next.

The CLI should keep the current small command surface and avoid promising a machine-readable JSON schema, while making the default terminal output much easier to read.

## Solution

Introduce a human-oriented renderer for Reconciler results. The renderer groups output by outcome, Component, risk, and next action; uses color only when appropriate for the terminal; and keeps non-TTY output deterministic and readable without color. Command failures should show the primary reason first, followed by specific guidance such as `rerun with --adopt`, `rerun with --allow-system`, provide `--github-key`, complete an Owner action, resolve stale state, or run `doctor`.

The Reconciler result model remains the policy seam. Rendering should be a CLI presentation layer over existing Result data, with only minimal Result additions if a concrete next-action fact cannot be derived safely from existing fields.

## User Stories

1. As an Owner, I want the first screen of `plan` output to show outcome, target, support level, and a grouped Component summary, so that I can immediately tell what will change.
2. As an Owner, I want changed Components to be visually distinct from unchanged, blocked, skipped, or healthy Components, so that I do not have to scan every path line.
3. As an Owner, I want changes grouped by Component and kind, so that I can review risky filesystem and system effects in a predictable order.
4. As an Owner, I want conflicts, blockers, Retirements, and System Changes highlighted before routine file writes, so that risky decisions are not buried.
5. As an Owner, I want command failures to show a concise reason and a next action, so that I know whether to rerun with `--yes`, `--adopt`, `--allow-system`, `--github-key`, or fix local state.
6. As an Owner, I want color in interactive terminals, but readable plain output in redirected logs and when `NO_COLOR` is set.
7. As an Owner, I want `doctor` output to group healthy and unhealthy checks, so that local drift and network diagnostics are easy to separate.
8. As an Owner, I want output to remain deterministic enough for tests and bug reports, so that a pasted plan is still useful for diagnosis.

## Implementation Decisions

- Rendering lives in the CLI package or a small internal presentation package, not inside Reconciler policy.
- The default renderer is human-readable text, not JSON.
- Color follows terminal conventions: auto color for TTY, no color for non-TTY, respect `NO_COLOR`, and provide an explicit override if needed.
- Non-TTY output keeps stable text and ordering, but may use the same grouped structure without escape codes.
- Summary sections come before detailed path listings.
- Next-action guidance is derived from Blocker codes, outcomes, conflicts, and change flags.

## Out of Scope

- A stable JSON output contract.
- Interactive selection, prompts beyond the existing authorization/key selection prompts, or a TUI.
- Changing Reconciler planning or mutation semantics.
- Hiding details needed for review; detailed paths must still be available in the default output.
- Localization beyond the existing English CLI vocabulary.

## Testing Strategy

- CLI-output tests should cover TTY and non-TTY rendering.
- Color tests should cover auto color, forced color, disabled color, and `NO_COLOR`.
- Snapshot-style assertions should focus on stable sections and key lines rather than ANSI implementation minutiae.
- Failure tests should cover Denied, Conflict, System Change authorization, Secret Reference required, Stale Plan, Pending Work, Partial, and Doctor unhealthy paths.
- Existing Reconciler contract tests should remain focused on Result semantics rather than presentation.

