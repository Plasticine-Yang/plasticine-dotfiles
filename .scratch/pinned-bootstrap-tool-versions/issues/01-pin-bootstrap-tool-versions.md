# 01: Pin chezmoi, Lazygit, and Neovim bootstrap versions

**What to build:** Make Base Dotfiles reliably bootstrap behind shared proxies by pinning chezmoi `2.72.1`, Lazygit `0.65.1`, and Neovim `0.12.5`, using exact official versioned assets and reviewed per-platform SHA-256 values instead of runtime GitHub Release discovery. Preserve the existing safe ownership, validation, publication, configuration, and retry behavior across the public installer and direct chezmoi entrypoints.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Chezmoi uses `2.72.1` as its fixed supported baseline and makes no GitHub release-metadata request.
- [ ] Lazygit uses `0.65.1` as its fixed supported baseline and makes no GitHub release-metadata request.
- [ ] Neovim uses `0.12.5` as its fixed supported baseline and makes no GitHub release-metadata request.
- [ ] Production execution for all three tools contains no direct `api.github.com` dependency and does not replace it with another moving `latest` lookup, API authentication, proxy retry, or runtime metadata cache.
- [ ] Missing tools download only exact versioned official Release assets constructed from their pins and selected platform mappings.
- [ ] Every supported artifact is verified against the reviewed SHA-256 value recorded with the corresponding pinned version; removing metadata lookup does not weaken integrity verification.
- [ ] Chezmoi continues to support the declared macOS/Linux and x86_64/arm64 routes, including appropriate glibc/musl selection where the pinned upstream release provides distinct assets.
- [ ] Lazygit and Neovim continue to support all four declared macOS/Linux and x86_64/arm64 asset mappings.
- [ ] A healthy stable installed version equal to or newer than its tool's pin is reused without downgrade, replacement, metadata lookup, or artifact download.
- [ ] An older Base-Dotfiles-managed direct installation is upgraded to the pin only after the complete candidate has been downloaded and validated.
- [ ] An older externally owned installation is left untouched with actionable owner-specific guidance; no shadow installation is published.
- [ ] Prerelease, custom, malformed, unhealthy, ambiguous, and unsafe installations retain the existing refusal and diagnostic behavior rather than being silently adopted or replaced.
- [ ] Fresh no-clobber publication, authorized-upgrade destination revalidation, race detection, atomic activation, and final health verification remain intact.
- [ ] Lazygit retains archive-member validation, executable-mode publication, configuration ordering, alias ownership, and preservation of unrelated state.
- [ ] Neovim retains safe archive-layout validation, rejection of archive links, complete runtime publication, candidate runtime checks, command-link ownership, configuration ordering, and post-configuration plugin synchronization.
- [ ] Chezmoi's explicit executable override remains locally validated and neither queried nor mutated through a release route.
- [ ] Existing Feature Selection behavior remains intact: chezmoi is prerequisite work, while Lazygit and Neovim perform tool preparation only when selected and confirmed; Preview, cancellation, dry-run, and unselected Features do not download their assets.
- [ ] Installer-entrypoint tests with disposable state prove all three pinned paths succeed when any attempted GitHub REST API request is forced to fail.
- [ ] Direct chezmoi-apply tests continue to cover the selected Lazygit and Neovim execution paths without live network access.
- [ ] Tests cover missing, older managed, equal, newer stable, unsupported-owner, unhealthy, prerelease/custom, checksum mismatch, unsafe archive, extraction/candidate failure, destination race, publication failure, and final-health cases at the existing public seams.
- [ ] Tests prove a newly published upstream release does not change the versions selected by an existing Base Dotfiles Release.
- [ ] Tests prove equal or newer stable installations produce no tool-release network request and retain their existing bytes or distribution.
- [ ] Release-pipeline verification proves the generated installer carries the pinned chezmoi version and integrity data and the released source carries the pinned Lazygit and Neovim version/digest mappings.
- [ ] Existing integration, combined-installation, runtime, configuration backup, mode preservation, source provenance, and retry regressions continue to pass after obsolete moving-target assertions are replaced.
- [ ] User documentation describes the fixed supported baselines, reviewed artifact verification, newer-version reuse, remaining versioned-download requirements, and the need for a new Base Dotfiles Release.
- [ ] Domain/spec documentation explicitly records that this decision supersedes the earlier runtime current-target/no-pin policy for these three binary distributions while preserving unrelated safety and ownership decisions.
- [ ] fnm, Herdr, Zsh, Homebrew, APT, Antidote, Neovim plugin versions, Tool-managed State, and the top-level Base Dotfiles latest-Release selector remain outside this change.
