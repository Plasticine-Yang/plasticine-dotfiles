# 12: Migrate Neovim configuration and current plugins on an existing editor

**What to build:** Give the Owner the complete migrated Neovim editing experience on a Workstation that already has the current stable editor. Deliver selection, the declared configuration, native plugin installation and updates, and real editor verification as one usable slice. Workstations needing editor installation or an executable upgrade receive a clear prerequisite error until ticket 13 adds that route.

**Blocked by:** 07 — Separate tool preparation from configuration effects.

**Status:** done

- [ ] Add Neovim to interactive and explicit non-interactive selection without implicitly selecting shell, fnm, or Git configuration. The installer and direct chezmoi application expose the same behavior.
- [ ] Preview performs local validation and describes current-target checking and plugin updates without a latest-release network query. During confirmed apply, establish that the existing executable is healthy and matches the official stable target before applying managed configuration.
- [ ] Missing, outdated, unhealthy, unverifiable, or incompatible editor installations fail with explicit installation/upgrade guidance and no selected configuration application. Do not silently claim full Neovim bootstrap, install through a package manager, or fall back to an old plugin set in this slice.
- [ ] Migrate exactly the nine inventoried Lua files from the approved spec, preserving the legacy editing behavior, theme, file tree, scrolling, surrounding, automatic pairs, jumps, and terminal shortcuts. Do not expand the plugin feature set or add language tooling.
- [ ] Adapt the configuration to current Neovim and plugin interfaces rather than retaining obsolete compatibility constraints. Remove numbered release and commit pins, use moving upstream plugin targets, and do not introduce a replacement version-lock mechanism.
- [ ] Bootstrap and update lazy.nvim through its native moving channel and perform native plugin installation/update on every selected apply. Completion is not deferred exclusively to the first interactive editor launch.
- [ ] Native plugin synchronization must use the intended managed configuration and native data locations, not a competing preexisting user entrypoint or an alternate data tree created to make installation succeed. Native lockfiles remain tool-managed results, not repository-pinned desired versions.
- [ ] Apply the selected whole-file protection from ticket 07. Validate all declared files and relevant parents before selected-tool mutation, preview differences, back up changed regular files, preserve existing modes, and leave identical content without extra writes or backups.
- [ ] Reject a competing editor entrypoint, unsafe selected configuration target, or unsupported non-default configuration environment rather than deleting it or silently managing a configuration the editor will not use.
- [ ] Preserve unrelated configuration files, Owner additions outside the declared inventory, plugin checkouts, caches, and state. Native plugin updates are permitted; importing, relocating, or cleaning legacy runtime data is not.
- [ ] Plugin setup/update and runtime verification must finish successfully before Neovim reports success. A failure after configuration application returns nonzero, reports remaining configuration/native changes, preserves backups, and supports a safe retry without pretending to roll back all native plugin effects.
- [ ] Before configuration application, a current-target lookup or preparation failure leaves selected managed configuration unchanged. In combined selections, plugin synchronization precedes final runtime readiness and the existing login-shell transition.
- [ ] Verify selection isolation, cancellation, dry-run, current/missing/outdated editor cases, unchanged configuration, changed-file backups, mode recovery, conflicting entrypoints, current plugin updates, and partial plugin failure/retry through public entrypoints in disposable homes.
- [ ] Use controlled release metadata and plugin-manager dependencies for deterministic automated tests. Use real Neovim to prove configuration startup, the migrated shortcuts, representative file-tree behavior, and terminal functionality; executable version output alone is insufficient.
- [ ] Perform a separately identified disposable-environment smoke check with current upstream plugins before claiming current-plugin compatibility. Do not make routine automated tests depend on live releases or alter the Owner's editor state.
- [ ] Document the existing-current-editor scope of this increment, standalone selection, exact configuration ownership, native plugin-update behavior, unsupported setup guidance, and partial-failure semantics. Include relevant installer, integration, and existing-feature regressions in the ticket, not only in final integration work.

## Comments

- Implemented on `agent/ticket-12-neovim-current` from the ticket 07/08 baseline. The public `install.sh --neovim` and direct chezmoi flows share selection, local preflight, exact nine-file ownership, whole-file backups/mode recovery, official stable comparison, native `Lazy! sync`, and post-sync runtime readiness.
- Deterministic coverage lives in `tests/neovim.sh`; it uses controlled Release/editor boundaries and disposable homes for preview, selection isolation, current/missing/outdated/unhealthy/lookup failures, conflicts, backups, modes, native failure and retry.
- A separately identified `PLASTICINE_LIVE_NEOVIM_SMOKE=1 ./tests/neovim-runtime.sh` run passed against the real current editor and current upstream plugins in a disposable HOME on 2026-09-13. It exercised startup, key mappings, nvim-tree and toggleterm without reading or changing Owner Neovim state.
- Ticket 13 remains the sole owner of official archive installation/updating; this ticket deliberately returns prerequisite guidance for a missing or non-current editor.
