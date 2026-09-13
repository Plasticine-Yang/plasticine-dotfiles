# 09: Migrate independently selectable Git configuration

**What to build:** Let the Owner select Git configuration from the existing installer, receive the legacy identity and shared preferences, and retain an authoritative local override. Deliver the complete configuration Feature with Preview, safe replacement, repeatable application, tests, and usage documentation.

**Blocked by:** 07 — Separate tool preparation from configuration effects.

**Status:** done

- [ ] Add Git configuration to interactive selection and the explicit non-interactive Feature Selection interface. It works alone and with existing Features in any option order; it does not implicitly select GitHub SSH or shell.
- [ ] Preserve the legacy shared identity and the agreed default initial branch and pull-rebase settings. Keep the Owner-controlled local override include last so native Git precedence allows local values to win.
- [ ] Manage only the declared shared configuration target. Do not read, traverse, back up, merge, create, or overwrite the local override during installation or Preview.
- [ ] Use the selected whole-file protection contract from ticket 07: validate target and relevant parents before selected-tool mutation, reject unsafe targets, preview changed regular files, create private backups before replacement, preserve existing modes, and avoid rewriting identical content or adding redundant backups.
- [ ] Direct chezmoi application follows the same selection, validation, backup, and preservation rules as the installer path. Unselected Git configuration remains excluded from feature-specific observation and mutation.
- [ ] Do not add an identity interview, credential helper, plaintext credential store, URL rewrite, or new Git installation/update route. Existing Git and OpenSSH remain prerequisites, not selected tool upgrades.
- [ ] Selecting Git configuration together with a tool whose preparation fails must leave the managed Git configuration and current-run backups unchanged. Cancellation and dry-run likewise apply no selected configuration changes.
- [ ] Use real Git in isolated homes to prove shared settings and local-override precedence. Make the local override contain a distinctive marker and verify it never appears in managed backup contents or Preview traversal output.
- [ ] Cover missing, identical, changed, unusual-mode, unsafe-target, and invalid-parent cases through installer and chezmoi entrypoints, plus combinations with GitHub SSH and shell and option-order independence.
- [ ] Keep the current installer, integration, shell, and Lazygit regressions green with controlled external commands. Tests do not mutate the developer's Git configuration or keys.
- [ ] Document selection, whole-file ownership, local customization, backup/retry behavior, and the absence of Git/OpenSSH updates or legacy cleanup. Mark this ticket done only after the complete behavior and relevant verification are delivered.
