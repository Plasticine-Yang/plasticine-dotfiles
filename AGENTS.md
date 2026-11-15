## Project workflow

### Testing

Run local checks through `scripts/check.sh`; suite selection and dependencies are documented in `README.md` under 本地验证.

### GitHub and CI

Use `gh` for workflow runs, failure logs, and releases: `gh run view <run-id> --log-failed`, `gh run watch <run-id>`, `gh release view`. If `gh` is not on PATH, check the package manager prefix before concluding it is unavailable. Reserve browser automation for UI-only actions.

### Commits

- Write commit descriptions and bodies in Chinese; Conventional Commit types and scopes may remain in English.
- Commit when a piece of development work is complete — after implementation and its relevant verification pass — instead of leaving finished changes uncommitted.
- Explicitly stage only this delivery's files, inspect `git diff --cached --name-status` and the staged diff, and preserve unrelated user changes and staged content.

### Worktrees and temporary files

- Create worktrees under the current repository root at `.worktrees/<name>/`, after confirming Git ignores the directory.
