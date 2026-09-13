# 08: Keep chezmoi current on every installer invocation

**What to build:** Have the installer obtain the latest stable chezmoi when missing, update an outdated supported installation, and avoid replacing an already-current installation. Report this as prerequisite bootstrap work, separate from selected Feature application and its confirmation.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Remove the fixed bootstrap release as desired state. Every installer invocation checks the current official stable target, including invocations with an already-compatible chezmoi or an empty Feature Selection.
- [ ] Use a coherent resolved release for one bootstrap operation and report its source, observed installed version, intended action, and result. Do not add a version-selection flag, persistent tool lock, or fallback release.
- [ ] A missing tool is installed through the official direct route; an outdated, positively identified installation is updated only through a permitted route. Do not overwrite an arbitrary explicit executable, mutate a prohibited package-manager owner, or silently install a shadowing second copy.
- [ ] An already-current supported installation is reused without unnecessary binary replacement. A current installation owned by another route can be accepted when its currency is demonstrable without mutating that owner.
- [ ] Metadata, download, integrity, candidate-health, or publication failure stops installation. A runnable older copy is not sufficient to report successful currency, and an unverifiable custom build, prerelease, or unsupported outdated owner receives explicit guidance rather than a downgrade or takeover.
- [ ] Direct candidates are staged and checked before activation. Preserve the working executable on preparation failure, retain fresh-install no-clobber protection, and abort on detectable destination changes during an upgrade instead of using stale observations.
- [ ] The newly selected executable must still satisfy the actual chezmoi interface requirements before it initializes, previews, or applies the source. Any necessary capability check is distinct from a fixed desired release.
- [ ] Preserve source-release provenance, repository revision selection, explicit testing/executable overrides, and the existing non-interactive interface. Do not reinterpret tool currency as permission to remove release provenance or unrelated integrity constraints.
- [ ] Explain before prerequisite mutation that chezmoi maintenance and source acquisition can happen before selected-feature confirmation. Cancelling that later confirmation prevents Feature effects but does not promise to undo completed bootstrap work.
- [ ] Checking chezmoi does not probe or update unselected Feature tools, Git, OpenSSH, or unrelated prerequisites, and does not run a broad package upgrade.
- [ ] Exercise missing, outdated, current, unhealthy, prerelease, unknown-owner, explicit-executable, failed-lookup, failed-download, and interrupted-publication cases through the installer entrypoint using controlled release and executable fixtures.
- [ ] Verify an unchanged target causes no unnecessary replacement and a newly published fixture target causes the next invocation to update. Cover prerequisite success followed by selected-feature cancellation without conflating the two scopes.
- [ ] Retain installer, integration, and release-entrypoint regressions; adapt their controlled bootstrap fixtures so tests never update the developer's real chezmoi or access the network. Document the new prerequisite update behavior and failure guidance.
