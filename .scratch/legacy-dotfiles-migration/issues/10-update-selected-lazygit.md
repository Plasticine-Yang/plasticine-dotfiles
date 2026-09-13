# 10: Update selected Lazygit to the latest stable release

**What to build:** Make selecting Lazygit check the current official stable release on every apply, install it when missing, and safely upgrade a supported outdated direct installation. Preserve the existing alias, native configuration, and repository state; an older but healthy executable is no longer a successful substitute for an update.

**Blocked by:** 07 — Separate tool preparation from configuration effects.

**Status:** ready-for-agent

- [ ] Reuse the existing Lazygit selection and official release route. Interactive installation, non-interactive installation, and direct chezmoi application reach the same latest-target behavior without a new update command or version flag.
- [ ] Preview forecasts the selected route and possible update without querying release metadata. Only confirmed apply resolves the latest stable target, even when an existing executable is healthy; cancelled and dry-run feature work performs no latest lookup or update.
- [ ] Resolve a coherent release and matching integrity information for the invocation. Preserve platform/architecture mapping, official artifact verification, archive-member validation, candidate health checks, and absence of a package-manager fallback.
- [ ] Distinguish missing, outdated, current, unhealthy, prerelease/custom, and unsupported-owner installations. Install missing tools and update positively identified outdated direct installations; accept a demonstrably current executable without replacing it.
- [ ] An outdated prohibited or ambiguous installation owner produces actionable failure rather than a package-manager command, replacement of the owner's executable, or installation of a second copy that shadows it. Do not silently downgrade or change a prerelease channel.
- [ ] Add a separate safe replacement path for authorized direct upgrades. Prepare and check the candidate before replacing the active executable, revalidate the destination, abort on detectable target races, and preserve the working installation when preparation fails.
- [ ] Retain atomic no-clobber behavior for fresh installation. Do not delete a published pathname on later failure based only on its earlier association with this invocation.
- [ ] Verify the resulting executable and the resolved target. Metadata, download, integrity, extraction, publication, or post-update health failures return failure even if the old executable can still run; retain useful state and report which effects completed.
- [ ] Keep alias composition and native configuration/runtime ownership unchanged. Preserve unselected namespaces, existing configuration bytes and modes, and one backup per changed shared entrypoint. Do not create configuration backups when the resolved target and configuration are already satisfied.
- [ ] Cover missing/current/older fixtures, a newly published target on the next run, unchanged-target convergence, malformed metadata, checksum failures, unsafe members, target races, and unsupported owners through public entrypoints.
- [ ] Verify isolation when Lazygit is unselected and correct preparation-before-configuration ordering in combination with shell and GitHub SSH. Keep the real-Zsh alias invocation and later Owner override regressions.
- [ ] Document the distinction between fresh no-clobber installation and authorized upgrade, permitted installation ownership, stable-target resolution, network failure semantics, and unchanged configuration/data ownership. Run focused and existing integration/release regressions without real downloads or host mutations.
