# Complete selected legacy migrations and keep selected tools current

Status: ready-for-agent

## Problem Statement

The Owner wants the remaining useful parts of the legacy workstation setup without bringing back its installation framework or every former Feature. Git configuration, Neovim, and fnm are still needed; uv, Zellij, and Traex Session Manager are not. The Owner also wants Herdr available through its official installer.

The current installer has already delivered GitHub SSH, shell, and Lazygit, but its version policy does not match the Owner's expectations. It usually accepts any healthy existing tool without checking for updates, the chezmoi bootstrap selects a fixed version, and the legacy Neovim configuration fixes multiple plugin releases and commits. Running installation again therefore does not mean the selected tools are current.

The Owner wants each installation invocation to install missing selected tools, upgrade outdated selected tools, and leave tools that already satisfy the current upstream target alone. Zsh is the explicit exception: its existing system/APT route is sufficient. Package-manager installation is not wanted for Neovim or Herdr; macOS fnm is explicitly allowed to use Homebrew, and the already-delivered shell routes remain in place.

## Solution

Keep the existing installer and chezmoi entrypoints. Add independently selectable Git configuration, Neovim, fnm, and Herdr Features alongside GitHub SSH, shell, and Lazygit. Do not recreate the legacy Plasticine CLI or add another package-management framework.

Change installation from missing-tool bootstrap to selected-tool currency maintenance. Every applying invocation obtains the current target from the permitted upstream route, installs or updates as needed, checks the result, and reports failure when currency cannot be established or achieved. Successful execution must not mean merely that an older executable still runs.

Use the latest official stable release for directly distributed tools, the latest available formula for Homebrew-backed tools, and moving upstream versions resolved by the native plugin managers for plugins. Do not introduce repository-maintained release pins, a Tool Lock, or a version-selection interface. Preserve the system/APT Zsh exception and keep unrelated prerequisite programs outside this update policy.

Preserve Preview, explicit confirmation, independent Feature Selection, configuration backups, Integration Block composition, native configuration locations, and Tool-managed State. Updates are not an all-or-nothing workstation transaction: completed native effects may remain after a later failure, but the installer must report the failure and support a safe retry.

The three unwanted legacy Features are no longer future migration work. This decision does not uninstall them from any Workstation or remove their configuration or data.

## User Stories

1. As the Owner, I want Git configuration to be selectable independently, so that I can apply shared Git preferences without installing an editor or changing my shell.
2. As the Owner, I want the legacy Git identity and shared preferences preserved, so that migration does not unexpectedly change my normal Git behavior.
3. As the Owner, I want my local Git override to remain under my control and take precedence, so that a company Workstation can use a different identity without changing Base Dotfiles.
4. As the Owner, I want Git configuration changes previewed and backed up, so that replacing an existing file is explicit and recoverable.
5. As the Owner, I want Git configuration and GitHub SSH to remain independent, so that selecting one does not silently select or reconfigure the other.
6. As the Owner, I want Neovim installed from official prebuilt distributions without a package manager, so that its installation does not introduce Homebrew, APT, or another manager.
7. As the Owner, I want the complete Neovim distribution, including its runtime, so that the installed editor works beyond printing a version.
8. As the Owner, I want my existing Neovim editing preferences and shortcuts preserved, so that I do not have to relearn the editor during migration.
9. As the Owner, I want the migrated Neovim configuration adapted to current plugins, so that obsolete compatibility pins do not prevent using current software.
10. As the Owner, I want only the declared Neovim configuration files managed, so that unrelated files in the editor's configuration directory are not deleted or adopted.
11. As the Owner, I want conflicting editor entrypoints reported rather than silently removed, so that another configuration is not destroyed to make installation succeed.
12. As the Owner, I want Neovim plugins installed and updated when I select Neovim, so that a successful installation does not defer the requested update until my first editor launch.
13. As the Owner, I want plugin checkout, cache, and lockfile operations delegated to lazy.nvim, so that Base Dotfiles does not become a second plugin manager.
14. As the Owner, I want fnm installed and updated through Homebrew on macOS, so that I follow its recommended macOS installation route.
15. As the Owner, I want fnm installed and updated through its official script on Linux, so that no package manager is introduced for that Feature.
16. As the Owner, I want fnm to be independently selectable, so that obtaining a Node version manager does not implicitly reinstall my entire shell setup.
17. As the Owner, I want the existing guarded fnm shell activation reused, so that migration does not create duplicate initialization or allow failed environment output to interrupt shell startup.
18. As the Owner, I want standalone fnm installation to explain any missing PATH or shell activation setup, so that independent selection remains understandable and usable.
19. As the Owner, I want Node versions, the selected default Node version, and fnm runtime data left alone, so that installing the manager does not change project runtimes.
20. As the Owner, I want Herdr bootstrapped through its official script, so that its platform selection and download behavior stay aligned with upstream.
21. As the Owner, I want Herdr installation to supply the command without launching it, so that installing a tool does not create sessions or start a background server.
22. As the Owner, I want Herdr configuration, agent integrations, and saved sessions left outside Base Dotfiles management, so that installation does not take over my workspace setup.
23. As the Owner, I want native updater prompts to remain explicit, so that an unattended installation cannot consent to stopping sessions or other native interventions on my behalf.
24. As the Owner, I want missing selected tools installed at the current permitted upstream target, so that a new Workstation does not start with an intentionally outdated release.
25. As the Owner, I want already-installed selected tools checked and upgraded on every applying invocation, so that rerunning installation is sufficient to bring them current.
26. As the Owner, I want tools already at the current target left installed without unnecessary replacement, so that checking for updates does not create avoidable churn.
27. As the Owner, I want stable releases rather than nightly or preview builds by default, so that using current software does not implicitly opt me into prereleases.
28. As the Owner, I want Zsh to retain its current system/APT policy, so that following the latest policy does not replace the system shell unnecessarily.
29. As the Owner, I want selecting shell to update Antidote, Powerlevel10k, and its plugin ecosystem through native mechanisms, so that shell components do not remain indefinitely at their first-installed versions.
30. As the Owner, I want chezmoi checked and updated as an installer prerequisite, so that the installer is not tied to a fixed bootstrap release.
31. As the Owner, I want configuration-only Features not to update unrelated Git or OpenSSH installations, so that the update scope remains the set of tools the installer actually owns or is authorized to maintain.
32. As the Owner, I want unselected Features left uninspected and unchanged by feature-specific work, so that installing one capability does not update my whole Workstation.
33. As the Owner, I want both interactive selection and explicit non-interactive options, so that the same behavior is available manually and from automation.
34. As the Owner, I want Preview to explain installation routes, update intent, configuration differences, network access, and privilege requirements, so that confirmation has a meaningful scope.
35. As the Owner, I want cancelling feature confirmation to avoid selected-tool updates and selected-configuration changes, so that reviewing a proposed installation does not apply it.
36. As the Owner, I want failed metadata lookup, download, verification, or update reported as failure, so that an old but runnable binary is not presented as successfully updated.
37. As the Owner, I want an unsupported or ambiguous update owner reported rather than silently replaced, so that the installer does not create competing installations or corrupt a package-manager installation.
38. As the Owner, I want compatible existing installation owners retained when their update routes are permitted, so that updating does not require a gratuitous ownership migration.
39. As the Owner, I want configuration and runtime data preserved across executable updates, so that staying current does not reset tool preferences or state.
40. As the Owner, I want malformed Integration Blocks and unsafe configuration targets rejected before selected-tool mutation, so that unrelated tools are not upgraded before an already-detectable configuration error is reported.
41. As the Owner, I want failed direct-download preparation to leave the current installation available, so that a bad candidate does not replace a working tool.
42. As the Owner, I want partial failures described accurately and reruns to resume from observed state, so that I can recover without an automatic uninstall or destructive rollback.
43. As the Owner, I want applicable macOS and Linux routes verified separately, so that a successful test on one platform is not mistaken for support on another.
44. As the Owner, I want uv, Zellij, and Traex Session Manager removed from the migration backlog without uninstalling them, so that the roadmap reflects what I actually intend to use.
45. As the Owner, I want installation behavior tested through the same entrypoints I use, so that passing tests demonstrate a usable feature rather than only correct internal helpers.
46. As the Owner, I want real Zsh and Neovim runtime checks in isolated homes, so that executable version checks alone do not conceal a broken interactive setup.
47. As the Owner, I want already-completed shell and Lazygit work recorded as historical delivery, so that the new update policy does not misrepresent earlier completed tickets as unfinished.

## Implementation Decisions

### Selection and scope

- Extend the existing Feature Selection interface with Git configuration, Neovim, fnm, and Herdr. Retain GitHub SSH, shell, and Lazygit. Interactive and non-interactive selection must describe and select the same capabilities, independent of option order.
- fnm does not implicitly select or require shell. A combined selection uses the existing shared activation; standalone selection reports any required native shell setup without editing an unselected shell configuration.
- Git configuration and GitHub SSH are configuration Features, not requests to install or upgrade Git and OpenSSH. Existing prerequisites remain prerequisites, not additional selected tools.
- Retire uv, Zellij, and Traex Session Manager from planned migration scope. No removal operation follows from that roadmap decision.

### Current-version policy

- Every applying invocation checks the current permitted upstream target for each selected tool, including an already healthy tool. Install when missing, upgrade when outdated, and avoid replacement when the target is already satisfied. Reusing a healthy executable without checking currency is no longer sufficient.
- Latest means the official stable release for direct release routes, the latest available formula after native metadata refresh for Homebrew routes, and the current moving upstream target selected by the native plugin manager for plugins. Where a plugin has no stable release channel, its maintained default branch is the moving target.
- Homebrew currency is relative to Homebrew's available formula and can lag an upstream release. The installer must report that source rather than claim the formula always equals the newest upstream binary.
- Resolve a coherent target during the confirmed apply and report the observed target and result. Do not continuously chase releases published during the same run. Refresh or resolve again on the next invocation.
- A latest lookup or update failure is a failure even if an older tool remains runnable. There is no silent offline success, automatic older-release fallback, or downgrade to satisfy an obsolete compatibility floor.
- An existing prerelease, a custom build with no comparable version, an unhealthy executable, or an unsupported update route must receive explicit guidance when the installer cannot safely establish and satisfy the policy. Do not silently switch release channels, replace an unknown owner, or describe an unverifiable installation as current.
- Remove the fixed chezmoi bootstrap release and the legacy Neovim plugin version constraints. Do not introduce fixed numbered releases, commit pins, a central tool-version manifest, or a user-facing version-selection mechanism for the affected tools.
- Resolving a release identifier and its integrity digest for one apply is not a persistent version pin. Native plugin lockfiles can continue to exist as Tool-managed State, but installation performs a native update rather than restoring old lock entries as desired versions.
- Zsh retains the existing healthy system installation or reviewed APT preparation route. It is not required to match the newest upstream release. This exception does not exempt Antidote or shell plugins from selected updates.
- Treat chezmoi currency as an installer-prerequisite responsibility on each installer invocation, even though chezmoi is not a selectable Feature. Base Dotfiles release provenance and unrelated CI dependency declarations are not tool-version selections and are not changed by this policy.

### Upgrade ownership and failure behavior

- Define permitted discovery, target resolution, update, and health behavior within each tool module. Do not implement a generic rule that replaces any executable found through command lookup.
- An unambiguously identified, permitted existing installation is updated through its appropriate route. A tool owned by a route that is not permitted may satisfy the request if it is demonstrably already current; if it needs an update, fail with actionable guidance instead of invoking a prohibited package manager or installing a shadowing second copy.
- Plan all selected routes and validate selected configuration targets before selected-tool mutation. Unsupported owners, unsafe targets, and malformed selected Integration Blocks must be detected as early as the available local evidence allows.
- Direct-download candidates are prepared and health-checked away from the active installation. Fresh publication retains no-clobber behavior. Updating an existing direct installation is a distinct, authorized replacement operation with destination revalidation and failure-safe publication; the previous create-only rule must not be mistaken for an upgrade implementation.
- Preserve the current installation until the candidate passes preparation and validation. Detectable target changes abort publication rather than authorizing a stale replacement. Do not delete a pathname after failure merely because it once referred to an installer-created object.
- Verify direct release downloads against the integrity information actually published upstream. Preserve the native verification of delegated official scripts and describe its limits accurately; do not claim that a health check or a checksum fetched from the same origin is an independent authenticity signature.
- External installers and native updaters are trusted code, not sandboxes. Preview lists known commands and effects but does not promise to enumerate all native side effects.
- Native package-manager dependency effects are disclosed as part of the permitted route. Never run a broad package upgrade or deliberately update unrelated Features to implement selected-tool updates.
- Do not automatically uninstall successful earlier work or downgrade native state when a later step fails. Return failure, identify completed and incomplete effects, retain recoverable configuration backups, and allow a subsequent invocation to reobserve and retry.

### Git configuration

- Migrate the legacy identity, default initial branch, pull-rebase preference, and final local override include without adding an identity interview or a second configuration system.
- Manage only the declared shared Git configuration file. Preserve the Owner-controlled local override, do not traverse it during Preview or backup, and do not merge it into the managed file.
- Use the same selected whole-file contract as other managed configuration: show differences, back up changed existing regular files, preserve existing modes, reject unsafe targets, and avoid writes or additional backups when content is unchanged.
- Do not add credentials, a plaintext credential helper, GitHub URL rewrites, or a dependency on the GitHub SSH Feature.

### Neovim

- Use official stable prebuilt archives on macOS and Linux for the supported architectures. Do not use Homebrew, APT, Cargo, a third-party installer, or AppImage as an alternate route. Missing archive prerequisites produce guidance rather than automatic package installation.
- Install and update the complete distribution as one coherent editor installation, including runtime assets, and expose its executable through the conventional user command directory. Do not publish only the executable from the archive.
- Preserve the intended legacy editing behavior while adapting the configuration to current Neovim and plugin interfaces. Compatibility with the old pinned plugin set is not a goal, and obsolete compatibility-only declarations must not be retained to keep old releases running.
- Manage exactly the nine inventoried Lua configuration files rather than taking ownership of the editor's whole configuration tree. Preserve unrelated files and runtime state; reject a competing editor entrypoint rather than deleting it.
- Keep lazy.nvim as the native plugin manager. Bootstrap it from its moving upstream channel, remove fixed plugin tags and commits, and explicitly run native plugin installation/update during every selected Neovim apply.
- Native plugin synchronization must use the intended managed configuration and the tool's native data locations, not execute an unrelated preexisting user entrypoint or install into a different data tree to make a test pass.
- Neovim success includes usable configuration and completed plugin synchronization. A failed synchronization is reported as failure even if the editor executable itself has updated successfully.
- Do not install language servers, language runtimes, fonts, or clipboard providers as an implicit extension of this migration. Preserve the existing plugin feature set rather than redesigning the editor.

### fnm

- macOS uses the official Homebrew formula for missing-tool installation and subsequent updates. This is the explicit exception to the preference against new package-manager installation. A missing Homebrew can use the existing reviewed bootstrap behavior, with its native terminal and credential requirements shown before feature confirmation.
- Linux uses fnm's official installation script for installation and updates, with shell-file editing disabled and the executable destination explicitly selected. Do not pass a fixed release selector or introduce a fallback package-manager route.
- Download a script completely before executing it. Use private staging and candidate validation for the script-based binary route; do not stream an incomplete network response into a shell or overwrite an existing installation before checking the candidate.
- Continue the existing guarded shell activation, including refusing to evaluate output from a failed fnm environment command. Do not introduce duplicate Integration Blocks or automatic directory-change version switching.
- Updating fnm updates the manager only. Node installations, the default Node version, project version declarations, and fnm's native data location remain outside this Feature's update scope.

### Herdr

- Bootstrap missing Herdr using its official installer, not a reimplementation of the release-manifest downloader and not a package manager. Use the installer-supported destination control to prepare a private candidate before publishing the command.
- Use Herdr's native update route for a positively identified direct installation. Resolve and verify the stable target rather than treating a successful invocation that made no update as sufficient evidence.
- Keep updater-required interventions explicit. Do not synthesize native confirmation, proactively stop sessions, request experimental live handoff, or silently change an Owner-selected channel. If an unattended upgrade cannot safely finish, return actionable failure instead of claiming success.
- Check the executable using its noninteractive version interface. Do not launch the terminal UI or a server as an installation health probe.
- Do not create aliases, modify shell startup files, install agent integrations, generate configuration, or manage session data. Explain command lookup requirements when Herdr is selected without shell.

### Existing shell and Lazygit

- Extend the already-delivered shell and Lazygit tool modules from missing-only preparation to the current-version policy, while retaining their configuration ownership and selected-only validation contracts.
- Keep the current permitted shell installation routes. Update Antidote and the shell plugin ecosystem through their native mechanisms; Powerlevel10k participates as a plugin rather than a separately pinned artifact.
- Preserve Owner-controlled plugin declarations and native caches and checkouts. Native updater effects within the selected ecosystem are allowed, but Base Dotfiles must not import, relocate, version, or clean that state as its own configuration.
- Lazygit continues using official release artifacts for its direct installation route. Add safe direct upgrades rather than switching fresh installation to a package manager. Preserve the existing alias and do not manage Lazygit configuration or repository state.

### Installer organization and execution order

- Reuse the current installer, chezmoi selection and filtering, tool planning/preview/preparation modules, and Integration Block composer. Extend these seams instead of introducing a second command surface or the legacy callback graph.
- Extract whole-file backup and mode coordination from the existing shell-specific implementation only as needed to share it with Git configuration and Neovim. Keep the caller interface small and selected-target based; do not build a generic reconciliation framework.
- Separate selected-tool preparation from configuration backup/application where they are currently coupled. After local validation and Preview, one feature confirmation authorizes the listed selected updates and configuration effects.
- Within confirmed feature application, resolve current targets and prepare/check selected executables before backing up or applying managed configuration. Apply configuration, perform any configuration-dependent native plugin synchronization, verify runtime readiness, restore recorded modes, and leave the existing login-shell transition last among these configuration-dependent actions.
- A failure before managed configuration application must not write that configuration. A later plugin-update or runtime-verification failure may leave already-applied configuration and native plugin changes; report this explicitly and preserve backups rather than claiming transaction-wide rollback.
- Existing dry-run and Preview surfaces do not update selected tools or resolve latest targets over the network. Preview forecasts update intent and permitted routes; the exact current target is resolved during confirmed apply.
- Bootstrap work required to run the entrypoint, including chezmoi currency and source acquisition, is reported separately from selected feature application. Feature cancellation does not promise to undo those prerequisite effects, but it prevents selected-tool updates and selected-configuration application.
- Non-interactive confirmation skips only Plasticine's own confirmation. It does not provide administrator credentials, answer an upstream terminal prompt, or authorize unrelated process control.

## Testing Decisions

- The Owner approved the existing installer and chezmoi user entrypoints as the primary test seam. Tests exercise the real selection, rendering, execution ordering, and outcomes through those entrypoints rather than creating a new internal test interface.
- Follow the existing installer, integration, shell, Lazygit, and runtime suites: disposable HOME/config/data/state directories; controlled subprocesses; real template rendering; and observable files, exit status, diagnostics, and command effects. Do not assert private helper names or incidental internal decomposition.
- Replace external downloads, release metadata, platform observations, package managers, credentials, and native updaters with controlled executable fixtures. Automated route tests must not download real releases, mutate the developer's Homebrew or APT state, change a real login shell, or start a real Herdr server.
- Exercise each new Feature alone, meaningful combinations with the existing Features, the complete intended selection, option-order independence, empty selection, interactive cancellation, and non-interactive validation. Verify that fnm does not implicitly select shell and that configuration-only Features do not upgrade Git or OpenSSH.
- For each versioned route, cover missing, older, current, newer/prerelease, malformed-version, unhealthy, unsupported-owner, and failed-currency-lookup states. A previously successful installation must update when the fixture publishes a new release, while an unchanged target must avoid unnecessary executable replacement and configuration backup.
- Cover latest stable selection rather than prerelease selection, fresh Homebrew metadata, the system/APT Zsh exception, and removal of persistent runtime version pins. Static versions in controlled test fixtures are test data, not production version policy.
- Verify that cancellation and dry-run cause no selected-feature mutations or latest-release queries. Test prerequisite bootstrap effects separately so source acquisition or chezmoi maintenance is not incorrectly attributed to selected feature application.
- Test failures in download, official script execution, integrity verification, archive extraction, candidate health, target publication, native update, plugin synchronization, and final runtime checks. Check nonzero outcomes and the documented remaining state rather than asserting a nonexistent global rollback.
- Test fresh no-clobber publication, observed destination races, failed candidate preparation preserving the active install, complete Neovim runtime publication, and prohibition of silent package-manager ownership replacement or command shadowing.
- Verify preflight rejection of selected symlinks and other unsafe configuration targets, malformed selected Integration Blocks, and conflicting Neovim entrypoints before selected-tool mutation. Unselected namespaces and configuration remain uninspected by feature-specific work.
- Verify Git configuration values and final local-override precedence with real Git in an isolated environment. Assert that the Owner override bytes remain unchanged and are excluded from managed backup and Preview traversal.
- Verify the exact Neovim managed-file inventory, preservation of unrelated configuration and native state, current plugin declarations, and observable native plugin synchronization on each selected apply. Include failure and retry after synchronization has partially completed.
- Use real Zsh processes to verify shared activation, PATH behavior, continued execution of later Owner code, no duplicate fnm initialization, selected shell plugin availability, and preserved Lazygit alias composition.
- Use real Neovim processes to verify startup, the migrated shortcuts, and representative plugin behavior, including file-tree and terminal functionality. Keep tests isolated; use controlled plugin fixtures for deterministic automated behavior and perform an explicitly separated disposable-environment smoke check against current upstream plugins before claiming compatibility with them.
- Test Herdr with a fixture whose version command is safe and whose default launch/server/session commands fail the test if invoked. Cover a native updater that cannot complete without additional interaction; installation must not fabricate that interaction or claim success.
- Cover macOS and Linux routing and both declared architecture families with fixtures, and run available real-runtime checks on the existing platform test matrix. No claim of platform support follows solely from a mocked version command.
- Retain regression coverage for GitHub SSH, selected Integration Block byte preservation, one backup per changed shared entrypoint, file-mode restoration, source isolation, and the release entrypoint. Update tests that intentionally asserted the old missing-only or fixed-version policy, not unrelated safety tests.
- Completion requires implementation, passing relevant automated and runtime verification, updated user documentation, and accurate tracker state. Publishing this spec does not mark the new work complete.

## Out of Scope

- Migrating uv, Zellij, or Traex Session Manager; automatically uninstalling any of them; or cleaning their aliases, configuration, caches, or data.
- Removing the legacy checkout or automatically cleaning any legacy-managed resources, historical backups, tool data, or login-shell choices.
- Recreating the legacy Plasticine CLI, callback graph, package batching framework, Tool Lock, persistent version-selection system, or versioned launcher architecture.
- Requiring Zsh itself to match the latest upstream release, replacing a healthy system Zsh solely for currency, or expanding the existing shell installation routes.
- Package-manager installation for Neovim or Herdr, package-manager installation for Linux fnm, or a new package-manager fallback for direct Lazygit installation. Existing shell routes and macOS fnm are the stated permitted exceptions.
- Automatic installation or upgrading of Git, OpenSSH, download/archive prerequisites, Node versions, language servers, fonts, or clipboard providers merely because a dependent Feature is selected.
- Automatic migration between ambiguous or prohibited installation owners, unrequested channel switching, downgrading custom or prerelease installations, or broad workstation package upgrades.
- Managing or relocating tool runtime state as Base Dotfiles configuration. Native plugin/updater operations required by a selected Feature are in scope; copying legacy state into a new ownership model is not.
- Launching Herdr during installation, creating sessions, managing a server, installing agent integrations, or automatically consenting to native process-control prompts.
- Redesigning the Neovim plugin feature set, adding a new Git identity workflow, adding shell directory-change hooks for fnm, or configuring an entire new shell when only fnm is selected.
- Guaranteeing a transaction across package managers, official scripts, plugin managers, configuration application, and login-shell changes. Destructive automatic rollback is not a substitute for accurate partial-failure reporting.
- Windows support, arbitrary Linux distribution support, nightly-by-default installation, or guarantees that a future upstream release will remain compatible without configuration maintenance.
- Removing unrelated release-provenance constraints, CI action integrity pins, or deterministic test-fixture versions under the label of tool currency.
- Implementation, installation on the Owner's Workstation, and creation of implementation tickets as part of this specification-only publication.

## Further Notes

### Decision and delivery status

This spec records the agreed design on 2026-09-13. It is ready for implementation, not a description of behavior already shipped.

The Owner explicitly confirmed the installer/chezmoi test seam with real Zsh and Neovim runtime verification. The final version-policy decision supersedes earlier proposals to accept any healthy existing tool, preserve old Neovim compatibility pins, defer plugin setup exclusively to first launch, or require fnm and shell to be selected together.

The Owner retained Homebrew for macOS fnm after reviewing upstream's preference. Neovim remains an official-archive installation on both supported operating systems. Zsh remains the sole selected tool with the explicit existing system/APT currency exception.

| Previously delivered work | Historical status |
| --- | --- |
| GitHub SSH | Already available; its key/configuration behavior is retained, not redesigned here |
| Shell selection and configuration, bootstrap, and verification | Tickets 01, 02, and 03 remain `done` for the contracts they originally implemented |
| Lazygit selection and alias, bootstrap, and verification | Tickets 04, 05, and 06 remain `done` for the contracts they originally implemented |
| Current-version maintenance, Git configuration, Neovim, fnm, and Herdr | New work specified here; not yet implemented or verified |
| uv, Zellij, and Traex Session Manager | Removed from future migration scope by Owner decision; not delivered, and not uninstalled |

The earlier shell/Lazygit increments deliberately retained healthy existing versions, and the initial Lazygit publication contract was create-only. Those historical choices were completed successfully; the upgrade behavior in this spec is new work, not a reason to relabel the old tickets. In any conflict between their historical missing-only criteria and this spec's current-version requirements, this spec defines the new work.

Historical tickets remain available as [01](issues/01-migrate-shell-configuration.md), [02](issues/02-bootstrap-shell-toolchain.md), [03](issues/03-verify-and-document-shell-migration.md), [04](issues/04-migrate-lazygit-selection-and-alias.md), [05](issues/05-bootstrap-lazygit.md), and [06](issues/06-verify-and-document-lazygit-migration.md).

A useful delivery sequence is current-version/shared-safety work alongside Git configuration, followed by Neovim, fnm, and Herdr, with verification and documentation in each increment. Separate implementation tickets can be derived later; none are created by publishing this spec.

### External interfaces and path contracts

These are user-visible contracts, not proposed implementation-file locations.

- Add `--git-config`, `--neovim`, `--fnm`, and `--herdr` to the existing non-interactive `install.sh -y` interface and to interactive selection. Preserve `--github-ssh`, `--shell`, and `--lazygit`.
- A combined invocation can select all four additions together with `--shell`; standalone `--fnm` remains valid. No per-tool version flag or separate update subcommand is required: applying installation already performs selected updates.
- Git configuration owns `~/.gitconfig` and retains the final include of `~/.gitconfig.local`. Preserve the legacy `user.name = plasticine`, `user.email = 975036719@qq.com`, `init.defaultBranch = main`, and `pull.rebase = true`; local overrides remain authoritative afterward.
- The Neovim inventory is `~/.config/nvim/init.lua`, `lua/basic.lua`, `lua/keybindings.lua`, `lua/colorschema.lua`, `lua/plugins.lua`, and the four files under `lua/plugins-config/` for neoscroll, nvim-tree, surround, and toggleterm. The relative Lua paths are all below `~/.config/nvim`. A competing `init.vim` is a preflight conflict, not a deletion candidate.
- Neovim's complete direct distribution uses a stable user installation location such as `~/.local/opt/neovim`, with its command exposed at `~/.local/bin/nvim`. Do not collapse its runtime into a standalone executable. Non-default native configuration roots or alternate app names are not silently managed at the default location; report an unsupported configuration when the managed configuration would not be used.
- Linux fnm uses `https://fnm.vercel.app/install` with `--skip-shell` and an explicit `--install-dir` for candidate preparation, then exposes the command at `~/.local/bin/fnm`. Do not pass `--release`; do not use the macOS `--force-install` bypass because macOS uses Homebrew. Continue `fnm env --shell zsh` without `--use-on-cd`, and do not set or relocate `FNM_DIR`.
- Herdr's official installer is `https://herdr.dev/install.sh`; its supported `HERDR_INSTALL_DIR` controls the candidate destination. The final command is `~/.local/bin/herdr`. Use `herdr --version` for executable health and the native `herdr update` route for supported direct-install updates; do not invoke `--handoff` automatically.
- Selecting shell continues to expose `~/.local/bin`. Other Features do not quietly take ownership of PATH or shell startup files when shell is unselected; they report command-location and activation requirements.
- The existing `shell` and `lazygit` Integration Blocks remain in Owner-controlled `~/.zshrc`; the Lazygit alias remains `lg='lazygit'`. No new fnm or Herdr alias block is required.

### Source baseline and upstream evidence

Legacy behavior is inventoried from `~/.plasticine-dotfiles` at commit `3deacd68d5f289be778a7ac4bf3e575fb9905bd7`. That commit is evidence, not an installation dependency or a version target. The new installer must not read or execute the legacy checkout at runtime. Migration preserves intended behavior rather than copying the legacy implementation architecture.

Official facts checked during design:

- [Neovim installation documentation](https://github.com/neovim/neovim/blob/master/INSTALL.md) provides official prebuilt archives for macOS and Linux, including both architecture families; it does not provide the proposed one-command shell installer. The local wrapper must preserve the archive's runtime layout.
- [fnm installation documentation](https://github.com/Schniz/fnm#installation) and [installer source](https://github.com/Schniz/fnm/blob/master/.ci/install.sh) describe the Homebrew default on macOS, script-based installation elsewhere, explicit install destination, and shell-edit suppression. The current script's binary download does not itself provide an independent signature or checksum-verification guarantee; do not claim otherwise.
- [fnm PR 131](https://github.com/Schniz/fnm/pull/131) explains the historical preference for a mature package manager instead of maintaining macOS installation machinery. This informed the Owner's macOS Homebrew exception, not a requirement to use Homebrew for Neovim.
- [Herdr installation and update documentation](https://herdr.dev/docs/install/) describes the official script, stable channel, and native updater. Updates can interact with older running servers; native intervention must not be silently authorized by Plasticine.
- [Herdr's official installer](https://herdr.dev/install.sh) currently resolves its manifest, verifies the binary's SHA-256, supports an installation-directory override, and only prints PATH guidance. It directly replaces its chosen destination and does not run the downloaded binary as a health check, which is why candidate staging and explicit executable validation are required.

A current-target policy intentionally gives up fixed-version reproducibility. Upstream API changes may require configuration maintenance, and a newest supported artifact may fail platform or runtime checks. The correct outcome is an explicit failed update with useful retained state, not an undocumented pin or fallback to an older release.
