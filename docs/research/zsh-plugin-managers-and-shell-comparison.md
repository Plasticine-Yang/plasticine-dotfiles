# Zsh Plugin Managers and Shell Comparison

Date: 2026-07-12

## Scope

This note answers three design questions for Plasticine:

- Should Antidote become a Managed Tool?
- Which zsh plugin manager style best fits Plasticine?
- How do fish, zsh, bash, and POSIX sh compare for login-shell and script-shell use?

## Project Constraints

Plasticine currently distinguishes:

- Managed Tool: exact Release-pinned command-line tool installed from Tool Lock artifacts under `~/.plasticine/tools/<tool>/<version>` with stable launch entries in `~/.plasticine/bin`.
- System Dependency: OS-owned capability such as zsh, git, OpenSSH, or CA certificates.
- Tool-managed State: plugins, caches, generated files, runtime directories, and nested ecosystems that are outside Plan, drift checks, backups, and Release guarantees.

Relevant local sources:

- `CONTEXT.md`
- `docs/adr/0023-leave-nested-tool-ecosystems-tool-managed.md`
- `docs/adr/0046-install-managed-tools-in-versioned-user-directories.md`
- `docs/adr/0058-update-managed-tools-only-through-tool-lock.md`
- `.scratch/plasticine-cli/spec.md`

## Antidote Findings

Antidote is a zsh-native plugin manager focused on performance. Its official README says it is a feature-complete zsh implementation of the legacy Antibody plugin manager and uses `.zsh_plugins.txt` bundle declarations.

Sources:

- https://raw.githubusercontent.com/mattmc3/antidote/main/README.md
- https://antidote.sh/install
- https://antidote.sh/commands
- https://antidote.sh/options

Key facts:

- Official install path is git clone to `${ZDOTDIR:-$HOME}/.antidote`; package-manager options include Homebrew, Arch AUR, and Nix Home Manager.
- GitHub releases expose source archives but no custom packaged assets.
- The normal zsh integration is `source /path/to/antidote/antidote.zsh` followed by `antidote load`.
- High-performance mode uses `antidote bundle < .zsh_plugins.txt > .zsh_plugins.zsh`, then sources the generated static file.
- `ANTIDOTE_HOME` controls where plugin bundles are cloned.
- Plugin entries can use annotations such as `branch:<name>`, `path:<subpath>`, and `pin:<SHA>`.
- `pin:<SHA>` pins plugin bundles at the plugin-manager level, but Plasticine should not treat those transitive plugins as Tool Lock verified artifacts unless Plasticine downloads and verifies them itself.

Implementation consequence:

Antidote can fit the Managed Tool model if Plasticine treats the verified source archive as the tool payload. However, existing Managed Tool code currently extracts a single executable file. Antidote needs a directory payload containing `antidote.zsh` and `functions/`, so Plasticine likely needs directory-payload support before Antidote can be modeled cleanly.

## Zsh Plugin Manager Comparison

| Tool | Fit for Plasticine | Notes |
|---|---|---|
| Antidote | Best fit | Zsh-native, simple declarations, static generated file option, source-only but tag archives can be Tool Lock inputs. |
| Sheldon | Strong alternative | Rust binary with prebuilt release artifacts, TOML config, lock/source workflow. Less zsh-native, but strong reproducibility shape. Source: https://raw.githubusercontent.com/rossmacarthur/sheldon/master/README.md |
| Zinit / Zi | Powerful but broad | Turbo loading, ice modifiers, snippets, completions, annex ecosystem. Large feature surface and more runtime behavior than Plasticine needs. Sources: https://zdharma-continuum.github.io/zinit/wiki/INTRODUCTION/ and https://zsh.pages.dev/docs/getting_started/overview |
| zcomet | Simple human-dotfiles option | Fast and minimal, but expects clone-on-missing logic in `.zshrc` and has no release artifacts. Source: https://zcomet.io/documentation/ |
| zplug | Not recommended for new Plasticine work | Broad feature set, lazy loading, cache, GitHub release handling, but stale release cadence and too much surface. Source: https://zplug.github.io/ |
| zgenom / zgen | Not preferred | Static init model is plausible, but zgen is old and zgenom has smaller footprint/no release artifacts. |

Recommendation:

Use Antidote for continuity with the existing dotfiles intent, but implement it conservatively:

- Managed Tool: Antidote source archive, extracted under `~/.plasticine/tools/antidote/<version>`.
- Managed configuration: zsh bootstrap that sources the versioned Antidote path and invokes static bundle generation.
- Managed path candidate: plugin declaration file, if the plugin set is part of the Owner Desired State.
- Tool-managed State: plugin clones, generated `.zsh_plugins.zsh`, snapshots, compinit dumps, `.zwc` compiled files, update logs, and plugin checkouts.

## Suggested Plasticine Design

### Minimal First Slice

1. Add `ManagedToolAntidote` to `internal/release`.
2. Extend Tool Lock to include Antidote for all Artifact Targets, probably using the same tag archive URL and SHA for every target because Antidote is source-only.
3. Add Managed Tool support for directory payloads. Current code extracts one executable by basename; Antidote needs `antidote.zsh` plus `functions/`.
4. Add Antidote resources to the `shell` Component, not a new public Component at first. Reason: Antidote is shell infrastructure, and the public Component graph already treats `shell` as owning zsh PATH/integration behavior.
5. Materialize zsh plugin declaration and bootstrap configuration:
   - `~/.plasticine/config/zsh/.zsh_plugins.txt`
   - generated static output under `~/.plasticine/runtime/antidote/static/.zsh_plugins.zsh`
   - plugin clone home under `~/.plasticine/runtime/antidote/home`
6. Update managed `.zshrc` to:
   - set `ANTIDOTE_HOME`
   - set snapshot/cache zstyles under `~/.plasticine/runtime/antidote`
   - source `~/.plasticine/tools/antidote/<version>/antidote.zsh`
   - regenerate static file only when the managed plugin declaration is newer
   - source the static file if present

### Boundary Rules

Plasticine should not:

- Own plugin repositories cloned by Antidote.
- Backup or drift-check generated static bundle files.
- Run `antidote update` automatically.
- Claim SHA-256 verification for plugin repos unless those plugins move into Plasticine Tool Lock.

Plasticine can:

- Pin Antidote itself.
- Pin the managed plugin declaration file.
- Relocate Antidote runtime roots under Plasticine Home.
- Let Antidote perform first-shell plugin clone/bundle generation as Tool-managed State.

### Open Design Choice

Whether `.zsh_plugins.txt` is Managed Path or Owner-controlled reference:

- Managed Path: reproducible Owner zsh experience, consistent across machines, but changing plugin list requires Release edit.
- Owner-controlled under runtime/config: flexible local edits, but weaker "one Desired State" story.

Given this repo is single-owner and opinionated, Managed Path is the better default.

## Shell Comparison

Sources:

- Fish docs: https://fishshell.com/docs/current/index.html and https://fishshell.com/docs/current/fish_for_bash_users.html
- Zsh manual: https://zsh.sourceforge.io/Doc/Release/Invocation.html and https://zsh.sourceforge.io/Doc/Release/Files.html
- Apple zsh default note: https://support.apple.com/en-us/102360
- Bash manual: https://www.gnu.org/software/bash/manual/html_node/What-is-Bash_003f.html and https://www.gnu.org/software/bash/manual/html_node/Bash-POSIX-Mode.html
- POSIX sh: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/sh.html

| Shell | Strengths | Weaknesses | Best use |
|---|---|---|---|
| fish | Best out-of-box interactive UX: autosuggestions, syntax highlighting, completions, friendly defaults. | Intentionally not POSIX-compatible; weaker fit for login shells on systems expecting Bourne-compatible profile behavior; not default on macOS/Linux. | Optional interactive shell for humans who value defaults over POSIX compatibility. |
| zsh | Strong interactive shell, mature completion/plugin ecosystem, macOS default since 10.15, enough Bourne/bash familiarity for many users. | Not POSIX-compatible by default; plugin-heavy setups can get complex without discipline. | Plasticine managed login shell. |
| bash | Very portable in practice, good script shell, POSIX mode exists, default/common on GNU/Linux. | Older default bash on macOS; interactive UX needs plugins/config to match fish/zsh. | Project scripts that intentionally need bash features. |
| POSIX sh | Maximum portability for bootstrap/system scripts. | Minimal interactive UX; no modern plugin ecosystem. | Bootstrap and portability-sensitive scripts. |

Recommendation for Plasticine:

- Keep zsh as the managed login shell.
- Keep POSIX sh for bootstrap and portable shell scripts.
- Use bash only for scripts that explicitly need bash features.
- Do not switch Plasticine's managed login shell to fish. Fish is excellent interactively, but it would introduce compatibility and support-floor work that does not match the current ADR direction.

