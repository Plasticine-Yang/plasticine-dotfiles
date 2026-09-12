# 05 — Bootstrap missing Lazygit

Status: ready-for-agent

Blocked by: 04

## What to build

Extend the Lazygit feature from configuring a healthy existing tool to preparing a missing tool directly from official GitHub Release assets on macOS and Linux. Keep route planning read-only, perform all selected configuration validation before tool effects, and apply the alias only after the resulting executable passes its health check. Do not invoke Homebrew, APT, `sudo`, `go install`, or a third-party installer.

## Acceptance criteria

- Supported platform/architecture handling covers Darwin and Linux on `x86_64`/`amd64` and `arm64`/`aarch64`; it maps them to the official archive spellings `darwin`/`linux` and `x86_64`/`arm64`. Unsupported targets fail before effects.
- Existing healthy Lazygit remains untouched regardless of version. An executable discovered on PATH, or an existing `~/.local/bin/lazygit` from the release route, must pass `--version`; unhealthy state is preserved and never triggers an owner switch.
- Missing Lazygit always uses the official release archive. Lazygit's repository does not contain an official install script: the upstream README links binary releases and provides a Linux command recipe. Plasticine implements the reviewed operations itself and uses a user-scoped destination instead of the recipe's `sudo install` into `/usr/local/bin`.
- Apply resolves the latest release tag, validates its shape, downloads the exact archive and same-release `checksums.txt`, requires exactly one matching valid 64-hex SHA-256 entry, and rejects missing, duplicate, malformed, or mismatched entries. The checksum and archive share the GitHub Release trust boundary; the implementation does not claim independent signature verification.
- Release extraction streams only the archive member named `lazygit` into private temporary storage, ignores archive path/mode metadata, assigns mode `0755`, checks `--version`, and atomically publishes to a validated real `~/.local/bin` directory. A target that appears during installation fails safely. Temporary files are cleaned on success, failure, and signals.
- Preview identifies the observed health, official release route, commands, network access, destination, checksum verification, post-install health gate, and lack of fallback. It states that Lazygit needs no package manager, privilege, credential, or terminal prompt. Preview and dry-run perform no network request, temporary write, or version resolution.
- A metadata/download/checksum/extraction/publish/post-health failure returns an actionable error, performs no fallback, and applies no alias or other selected configuration.
- All selected tools are prepared before configuration backup, mode normalization, and chezmoi target application. If an earlier selected tool was installed before a later tool failed, the healthy installation is retained and rerun resumes without reinstalling it.
- Lazygit installation is independent of `shell`: selecting only Lazygit never installs or probes Zsh/Antidote and never invokes `chsh`. The release route does not mutate PATH; documentation points Lazygit-only Owners at their existing PATH responsibility.
- The feature does not inspect, back up, import, rewrite, or remove `~/.config/lazygit`, Lazygit cache/log data, repository-local state, or any legacy runtime state. It does not update or remove an already healthy release binary.
- Tests use fake platform metadata, release metadata, curl, checksums, archives, health commands, filesystem races, and atomic publication. They cover both operating systems and architectures, every failure gate, non-regular destinations/parents, cancellation, partial success, and rerun recovery without package-manager or network access.

## Source references

- Legacy route implementation, including its Linux release path: `~/.plasticine-dotfiles/lib/plasticine/features/lazygit.sh` at commit `3deacd68d5f289be778a7ac4bf3e575fb9905bd7`
- Legacy deterministic route coverage: `tests/portable/lazygit_test.sh` at the same commit
- Current native-install precedent: `lib/shell-bootstrap.sh` and the shell apply scripts in this repository
- Current official-source findings: `../lazygit-installation-research.md`

## Comments
