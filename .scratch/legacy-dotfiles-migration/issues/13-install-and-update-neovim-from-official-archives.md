# 13: Install and update Neovim from official stable archives

**What to build:** Extend the migrated Neovim experience to new Workstations and supported outdated direct installations. Selecting Neovim obtains the current official archive without a package manager, prepares a coherent editor distribution, and completes the existing configuration and plugin-update flow before reporting success.

**Blocked by:** 12 — Migrate Neovim configuration and current plugins on an existing editor.

**Status:** done

- [ ] Replace ticket 12's missing/outdated-editor prerequisite error with the permitted official-archive installation and update route. Keep the current-editor path, independent selection, and configuration/plugin behavior already delivered there.
- [ ] Support the declared macOS and Linux platform/architecture combinations using official stable prebuilt archives. Do not invoke Homebrew, APT, Cargo, a third-party installer, or AppImage; missing download or extraction prerequisites produce guidance rather than package installation.
- [ ] Preview describes the archive route, platform mapping, final installation effect, integrity checks, and update intent without resolving latest metadata. Confirmed apply resolves a coherent stable target on every selected invocation, including healthy existing installations.
- [ ] Install and publish the complete distribution, including runtime assets, as one coherent installation with a usable command entry. Do not copy only the executable, mix old and new runtime files, or introduce a version-selection interface or persistent tool lock.
- [ ] Use the integrity evidence actually available from upstream, safe archive validation/extraction, candidate health checks, and runtime validation before activation. State trust limitations accurately rather than inventing checksum or signature guarantees.
- [ ] Missing tools receive a safe fresh installation. Positively identified outdated direct installations receive an authorized upgrade; a demonstrably current installation avoids unnecessary distribution replacement while native plugin checking still runs.
- [ ] Already-current tools owned by another route may be accepted without mutating that route when currency is demonstrable. An outdated prohibited or ambiguous owner fails with guidance; do not call its package manager, overwrite it, or publish a shadowing second installation.
- [ ] Preserve the active editor until candidate preparation and checks pass. Retain fresh no-clobber protection, distinguish upgrade replacement from creation, revalidate the active target and command entry, and abort on detectable destination races.
- [ ] Publication or health failure returns nonzero with accurate retained-state guidance. Do not delete a pathname after failure based on an earlier identity, silently downgrade, switch a prerelease channel, or label a remaining old executable as updated.
- [ ] Prepare and check the selected editor before managed configuration effects. Then run the existing protected configuration application and native plugin synchronization against the actual selected installation; successful version output alone does not complete the Feature.
- [ ] Preserve the declared configuration inventory, unrelated Owner files, plugin-manager state ownership, and conflict checks from ticket 12. Binary updates must not reset editor configuration or clean native caches and data.
- [ ] Verify fresh installation, outdated direct upgrade, current-target convergence, a new upstream target on the next run, unsupported owner/platform, malformed metadata, failed verification/extraction, complete runtime layout, target races, and publication failure through installer and chezmoi entrypoints.
- [ ] Cover binary preparation failure before configuration and native plugin failure after configuration, including retry and preservation of the previous usable installation where preparation never completed. Use controlled archives, metadata, filesystem events, and subprocesses without live downloads in routine automated tests.
- [ ] Use real Neovim in isolated runtime tests to verify the selected distribution can load its runtime, migrated configuration, and representative plugin behavior. Retain ticket 12's explicit smoke-check requirement for current upstream plugin compatibility.
- [ ] Update usage documentation to remove the temporary existing-current-editor restriction and describe official archive installation, upgrades, installation-owner refusals, PATH responsibility, platform support, and recovery. Run focused tests and the existing configuration, installer, integration, and release regressions.

## Comments

- Implemented on `agent/ticket-13-neovim-archive` from baseline `89d50d7`. The existing Neovim selection/configuration/plugin flow now plans and prepares official stable archives before any managed configuration effect.
- The route maps macOS/Linux and x86_64/arm64 to official archives, verifies the Release API SHA-256 asset digest and safe complete runtime layout, checks the candidate with its packaged runtime, and publishes `~/.local/opt/neovim` plus `~/.local/bin/nvim`.
- Fresh publication is no-clobber; only the managed link/distribution pair is an authorized upgrade owner. Current external owners are retained, while outdated/ambiguous/custom/prerelease owners fail without a shadow installation. Deterministic tests cover fresh/current/next-target convergence, failure preservation, complete runtime, owner refusal, destination races, and plugin failure/retry.
