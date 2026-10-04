# Issue tracker: Local Markdown

Issues and specs for this repo live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`, never a single combined tickets file
- Triage state is recorded as a `Status:` line near the top of each issue file (see `triage-labels.md` for the role strings)
- Dependencies are recorded as a `Blocked by: NN, NN` line near the top of each issue file
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/` (creating the directory if needed).

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Completing implementation tickets

Set `Status: done` only after the acceptance criteria are met and relevant verification passes. Append a completion note and verification results, then commit the implementation, necessary documentation, and ticket state together in Chinese. If the commit fails, fix it and complete the commit before reporting completion. Project setup does not complete existing tickets.

Exclude `done`, `wontfix`, and wayfinder's `resolved` from pending-development queries and the frontier. An implementation ticket is actionable only when every implementation dependency is `done`. A dependency marked `wontfix` requires reassessing the dependency relationship rather than automatically unblocking the ticket.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`). Research, prototype, and grilling tickets use `claimed`/`resolved`; implementation tickets with `Type: task` finish as `done`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved` or `done`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved` for research, prototype, or grilling (or `Status: done` for verified implementation tasks), then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`. Preserve the meaning of existing `resolved` records.

## File purpose and Git tracking

Specs, maps, and numbered tickets are long-term task records committed with the code. Store screenshots, recordings, logs, raw downloads, temporary scripts, and intermediate files in the ignored `.agent-tmp/<task>/` directory.

The default Git whitelist for `.scratch/` (and legacy `.Scratch/`) permits only `spec.md`, `map.md`, and `issues/NN-*.md`. Temporary Markdown is an intermediate file too. Put new long-term findings and attachments in formal project documentation; existing long-term material may use an exact `.gitignore` exception with its purpose documented here. Ticket and map conclusions must stand on their own without local temporary screenshots.

Retained exception: `.scratch/legacy-dotfiles-migration/lazygit-installation-research.md` records source-backed installation findings referenced by the migration ticket. Keep it tracked at its existing path.
