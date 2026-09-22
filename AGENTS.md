## Agent skills

### Issue tracker

Issues and specs are tracked as local Markdown under `.scratch/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five default triage roles plus the terminal `done` state; completed and verified tickets transition to `done`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses the single-context domain-doc layout. See `docs/agents/domain.md`.

## Repo conventions

### Testing

Do not add unit tests for UI. UI concerns (shell prompt, Neovim configuration, CLI presentation) are verified through the runtime and integration scripts under `tests/`, not with unit tests.

### Commits

- Write commit messages in Chinese.
- Commit when a piece of development work is complete — after implementation and its relevant verification pass — instead of leaving finished changes uncommitted.
