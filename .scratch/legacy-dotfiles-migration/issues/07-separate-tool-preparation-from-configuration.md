# 07: Separate tool preparation from configuration effects

**What to build:** Make the existing shell and Lazygit installation flows validate selected configuration first, prepare every selected tool before configuration effects, and share the established whole-file protection contract. This is the prefactoring slice for the approved migration spec: existing Features remain usable and their current missing-only version policy remains unchanged in this ticket.

**Blocked by:** None (can start immediately).

**Status:** done

- [ ] Existing installer and chezmoi entrypoints remain authoritative. Interactive selection, non-interactive selection, Preview, cancellation, and direct chezmoi application continue to work without a second command surface.
- [ ] Every selected configuration target and selected Integration Block namespace is validated before the first selected-tool mutation. Validation is repeated as appropriate during apply so Preview-time observations are not treated as permanent authorization.
- [ ] Separate shell tool preparation from configuration backup, permission normalization, and application. All selected tools must prepare successfully before those configuration effects begin; a later selected-tool failure must not leave earlier configuration backups or writes from the current invocation.
- [ ] Reuse a small selected-target whole-file protection module for existing shell configuration, suitable for the subsequent Git and Neovim slices. Preserve changed-file backups, private backup permissions, existing target modes, unsafe-target rejection, and unchanged-content convergence. Do not introduce a generic reconciliation or plugin framework.
- [ ] Preserve the existing Integration Block composer: selected-only validation, byte preservation outside selected blocks, deterministic insertion of missing blocks, in-place replacement of existing blocks, and one backup for one changed shared entrypoint.
- [ ] Preserve mode recovery after interrupted application and keep the login-shell transition after configuration application and mode restoration. The stage split must support later configuration-dependent runtime work without performing that future work in this ticket.
- [ ] Preserve GitHub SSH behavior and the existing safety validations when it is selected together with shell or Lazygit. Reordering must not move its configuration mutations ahead of validation or the selected-tool preparation gate.
- [ ] Do not change installation owners, latest-version behavior, accepted healthy versions, tool routes, or existing native plugin bootstrap behavior in this prefactor. Do not add new selectable Features yet.
- [ ] Failures accurately distinguish completed tool preparation from unapplied configuration. Do not automatically uninstall successful native work or delete runtime state to simulate rollback.
- [ ] Add entrypoint-level failure-ordering tests in disposable homes, including malformed selected blocks, a later preparation failure, interrupted mode restoration, cancellation, and a satisfied rerun. Use controlled executables and assert observable commands, bytes, permissions, backups, and exit status rather than private helper structure.
- [ ] Run the existing installer, integration, shell, Lazygit, real-Zsh runtime, and release regressions. No test invokes a real package manager, native credential prompt, login-shell change, or live download.
- [ ] Keep user-facing descriptions of configuration protection and partial failure accurate; do not advertise the later current-version policy as delivered by this ticket.
