## Agent skills

### Issue tracker

Specs, maps, and numbered tickets are tracked as local Markdown under `.scratch/<feature>/`. Before creating, reading, completing, or finding actionable tickets, read `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage roles plus the terminal `done` state. Before classifying, transitioning, or querying tickets, read `docs/agents/triage-labels.md`.

### Domain docs

This repo uses the single-context domain-doc layout. Before exploring code, read `docs/agents/domain.md` for the glossary and ADR paths.

### Adding a tool Feature

Before implementing a new independently selectable tool, read `docs/agents/adding-a-feature.md` for the canonical touchpoint list and order.

## Project workflow

### Testing

Do not add unit tests for UI. UI concerns (shell prompt, Neovim configuration, CLI presentation) are verified through the runtime and integration scripts under `tests/`, not with unit tests.

Test non-UI logic according to project conventions. Preserve and run applicable existing checks.

Run local checks through `scripts/check.sh`; suite selection and dependencies are documented in `README.md` under 本地验证.

### GitHub and CI

Use `gh` for workflow runs, failure logs, and releases: `gh run view <run-id> --log-failed`, `gh run watch <run-id>`, `gh release view`. If `gh` is not on PATH, check the package manager prefix before concluding it is unavailable. Reserve browser automation for UI-only actions.

### Commits

- Write commit descriptions and bodies in Chinese; Conventional Commit types and scopes may remain in English.
- Commit when a piece of development work is complete — after implementation and its relevant verification pass — instead of leaving finished changes uncommitted.
- Complete development tickets according to `docs/agents/issue-tracker.md`, then commit their `Status: done` updates together with the implementation.
- Explicitly stage only this delivery's files, inspect `git diff --cached --name-status` and the staged diff, and preserve unrelated user changes and staged content.

### Worktrees and temporary files

- Create worktrees under the current repository root at `.worktrees/<name>/`, after confirming Git ignores the directory.
- Store screenshots, recordings, logs, raw downloads, temporary scripts, and intermediate files in the ignored `.agent-tmp/<task>/` directory. Use `.scratch/` for task records; move new long-term findings and attachments into formal project documentation and update references. Existing retained materials follow the exceptions documented in `docs/agents/issue-tracker.md`.
