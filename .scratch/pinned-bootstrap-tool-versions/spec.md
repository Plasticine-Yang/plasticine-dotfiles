# Pin bootstrap tool versions and remove runtime GitHub API lookups

Status: ready-for-agent

## Problem Statement

The Owner needs Base Dotfiles to bootstrap a new Workstation reliably behind a shared corporate proxy. The current installer performs unauthenticated GitHub Releases API requests to establish the latest stable versions of chezmoi, Lazygit, and Neovim. GitHub grants these requests a small quota per public source IP. A shared proxy can exhaust that quota even on a new Workstation, causing GitHub to return HTTP 403 before the requested setup can complete.

The failure is especially disruptive for chezmoi because its currency check is prerequisite work on every installer invocation, before source acquisition and Feature confirmation. Lazygit and Neovim have the same failure mode after their Features are selected and confirmed. A healthy installation is not sufficient under the current current-target policy: failure to query upstream metadata is treated as failure to prove currency.

Observed evidence from the affected Workstation showed an unauthenticated GitHub `core` limit of 60 requests, all 60 consumed, and zero remaining. Repeating the request through a load-balanced proxy produced a different remaining quota, while a direct request had a mostly unused quota. This establishes shared proxy egress exhaustion as the cause rather than an unavailable repository, TLS failure, or invalid local executable.

The current moving-target policy also makes an installer Release less reproducible: the same released installer can choose different binary versions on different days. It introduces upstream metadata availability as an unnecessary prerequisite even when an installed stable version already satisfies the tool's required interface.

## Solution

Pin the versions that Base Dotfiles is permitted to install for the three direct-distribution tools: chezmoi `2.72.1`, Lazygit `0.65.1`, and Neovim `0.12.5`. Pin the matching official asset names and SHA-256 digests for every supported operating-system and architecture route. Construct versioned official GitHub Release download URLs locally and remove runtime GitHub Releases API metadata requests for these tools.

Treat each pin as the minimum stable version Base Dotfiles is prepared to install, not as authority to downgrade a newer stable executable. Reuse an existing healthy stable version when it is equal to or newer than the pin. Upgrade an older installation only when its ownership is a route that Base Dotfiles is already authorized to mutate. Continue to reject unhealthy, prerelease, custom, ambiguous, or unsafe installations rather than silently taking them over.

Preserve the current integrity, archive-layout, candidate-health, runtime-health, ownership, race-detection, no-clobber, and atomic-publication protections. Removing release metadata lookup must not weaken artifact verification. In particular, Neovim's asset digests must become reviewed release data because Neovim does not publish separate checksum assets for these archives.

The pins advance only through a reviewed Base Dotfiles change and a new Base Dotfiles Release. Other selected tools and native managers retain their current update policies. Neovim plugin synchronization remains delegated to lazy.nvim and is not made reproducible by pinning the Neovim binary.

## User Stories

1. As the Owner, I want a new Workstation to bootstrap without consuming an unauthenticated GitHub API request, so that a shared proxy's exhausted API quota cannot block all installation.
2. As the Owner, I want chezmoi pinned to `2.72.1`, so that its prerequisite version is known before the installer runs.
3. As the Owner, I want Lazygit pinned to `0.65.1`, so that selecting Lazygit does not require discovering a moving target.
4. As the Owner, I want Neovim pinned to `0.12.5`, so that selecting Neovim does not require discovering a moving target.
5. As the Owner, I want a released installer to resolve the same three binary targets on every invocation, so that installation behavior is reproducible over time.
6. As the Owner, I want compatible existing chezmoi installations reused without a metadata or artifact request, so that routine installer reruns do not depend on release services unnecessarily.
7. As the Owner, I want an existing Lazygit at or above the pinned stable version reused without a metadata or artifact request, so that applying its configuration remains reliable and does not replace a healthy command.
8. As the Owner, I want an existing Neovim at or above the pinned stable version reused without a release metadata or editor-archive request, so that a healthy editor is not downloaded again.
9. As the Owner, I want newer stable installations accepted, so that a manual or package-manager upgrade does not make Base Dotfiles demand a downgrade.
10. As the Owner, I want Base Dotfiles never to downgrade chezmoi, Lazygit, or Neovim to its pin, so that newer working installations remain intact.
11. As the Owner, I want missing tools installed from exact official versioned assets, so that an upstream `latest` pointer cannot change the selected binary.
12. As the Owner, I want an older Base-Dotfiles-managed direct installation upgraded to the pin, so that the installation reaches the supported baseline.
13. As the Owner, I want an older externally owned installation left untouched with actionable guidance, so that Base Dotfiles does not overwrite a package-manager or other Owner's command.
14. As the Owner, I want explicit executable overrides validated locally without an upstream currency lookup, so that tests and deliberate executable selection remain isolated.
15. As the Owner, I want prerelease and custom builds reported rather than silently replaced, so that pinning does not become an implicit channel switch.
16. As the Owner, I want unhealthy or unverifiable executables reported before publication, so that a broken command is not mistaken for a supported stable installation.
17. As the Owner, I want each supported platform mapping fixed alongside its version, so that a known release always selects the intended archive.
18. As the Owner, I want all downloaded archives checked against reviewed SHA-256 values, so that removing metadata lookup does not remove integrity checking.
19. As the Owner, I want checksum mismatches to fail before replacing an active installation, so that corrupted or unexpected downloads do not become active commands.
20. As the Owner, I want archive member and layout checks retained, so that a matching download route cannot publish an unsafe archive layout.
21. As the Owner, I want candidate version and health checks retained, so that an asset must actually provide the pinned tool before publication.
22. As the Owner, I want Neovim's complete runtime checked before activation, so that a standalone executable without its runtime is not reported as a usable editor.
23. As the Owner, I want fresh installations to retain no-clobber publication, so that a destination appearing during preparation is not overwritten.
24. As the Owner, I want authorized upgrades to revalidate their destination before replacement, so that a concurrent Owner change is not overwritten.
25. As the Owner, I want the existing working command preserved when download, checksum, extraction, candidate validation, or publication fails, so that retry remains safe.
26. As the Owner, I want Lazygit alias application to occur only after its selected binary is healthy, so that a failed binary preparation does not create incomplete configuration.
27. As the Owner, I want Neovim configuration to occur only after editor preparation succeeds, so that a failed binary preparation does not create an unusable managed configuration.
28. As the Owner, I want Neovim plugin synchronization to continue after the fixed editor and configuration are ready, so that pinning the editor does not silently remove the existing plugin-readiness behavior.
29. As the Owner, I want Preview and cancellation to remain local for selected Features, so that merely inspecting changes does not download tools or update native state.
30. As the Owner, I want an empty Feature Selection to perform no Lazygit or Neovim work, so that those pins do not broaden prerequisite scope.
31. As the Owner, I want an installer invocation with an already-compatible chezmoi to avoid all chezmoi release traffic, so that the prerequisite no longer has a moving-network dependency.
32. As the Owner, I want a missing or obsolete chezmoi to download only its fixed asset and required integrity material, so that bootstrap network access is minimal and deterministic.
33. As the Owner, I want supported older Linux environments to receive the correct chezmoi libc-compatible artifact where upstream publishes one, so that removing the official installer does not accidentally narrow Linux compatibility.
34. As the Owner, I want unsupported platform or libc combinations rejected with guidance, so that an incompatible binary is not published optimistically.
35. As the Owner, I want production paths for these tools to contain no `api.github.com` dependency, so that the original shared-quota failure cannot recur under another selected Feature.
36. As the Owner, I want direct versioned GitHub downloads to remain subject to normal error handling, so that proxy, network, or upstream download failures are reported accurately rather than confused with API rate limits.
37. As the Owner, I want the fixed versions documented as Base Dotfiles release inputs, so that I can tell what a published installer will install without executing it.
38. As the Owner, I want pin upgrades to require code review and a new Base Dotfiles Release, so that version changes and their checksums are deliberate and auditable.
39. As the Owner, I want historical current-target decisions explicitly superseded for these three tools, so that maintainers are not asked to satisfy contradictory specifications.
40. As the Owner, I want unrelated Feature update behavior left unchanged, so that solving GitHub API exhaustion does not silently redesign fnm, Herdr, shell, or plugin ownership.
41. As the Owner, I want the generated release installer to carry the same pinned chezmoi policy as the source installer, so that testing the repository reflects the command used on a fresh Workstation.
42. As the Owner, I want automated tests to reject any reintroduction of GitHub release-discovery requests for the three pinned tools, so that the same quota regression cannot return unnoticed.
43. As the Owner, I want tests to prove that a newly published upstream version does not change an existing Base Dotfiles Release's target, so that pinning is behavioral rather than documentary.
44. As the Owner, I want the current configuration, Tool-managed State, and backup ownership boundaries preserved, so that a version-policy change does not expand what Base Dotfiles manages.

## Implementation Decisions

- Pin chezmoi at stable version `2.72.1`, Lazygit at stable version `0.65.1`, and Neovim at stable version `0.12.5`. These values were the selected stable targets when this specification was produced on 2026-09-13.
- The pins are repository-owned release inputs. Advancing a pin requires updating the reviewed version, its complete supported asset mapping, its digests, tests, documentation, and then publishing a new Base Dotfiles Release. Runtime discovery must not silently advance them.
- Remove direct unauthenticated GitHub REST API release discovery for these three production paths. Do not add authentication, retry across proxy exits, cache mutable API responses, scrape a latest-release page, or substitute another moving `latest` endpoint.
- Construct downloads from the fixed tag and reviewed upstream asset naming conventions. Downloads remain on the tools' official GitHub Release locations and continue to require HTTPS.
- Store the expected SHA-256 value for every supported artifact with the corresponding pin. The version, asset name, and digest are one coherent reviewed tuple; an incomplete tuple is an unsupported route rather than permission to download without verification.
- For chezmoi `2.72.1`, retain the existing minimum required interface as `2.72.1`. A healthy stable installed version greater than or equal to that baseline is accepted without release traffic. A missing command or an older authorized direct installation is brought to `2.72.1`.
- Preserve chezmoi's explicit executable override: resolve it, validate the required interface, do not mutate its owner, and do not perform release traffic.
- Preserve chezmoi platform support for macOS and Linux on x86_64 and arm64. Match the official fixed-release libc selection where applicable, including the published Linux musl x86_64 variant, rather than assuming every Linux x86_64 host can execute the same glibc artifact. Unsupported combinations fail before publication.
- For Lazygit and Neovim, treat the pin as the Base-Dotfiles-managed installation baseline. Healthy stable versions equal to or greater than the pin are accepted. Versions below the pin are upgraded only when the existing installation is the authorized managed direct owner.
- A stable version greater than the pin must not be downgraded or rejected merely for being newer. Its ownership remains untouched. This acceptance does not claim that the newer version was installed or certified by the current Base Dotfiles Release.
- Continue rejecting prerelease, custom, malformed, or unverifiable versions because they cannot be safely ordered against the stable baseline without changing channels or ownership.
- Preserve existing external-owner rules. An older external executable receives actionable guidance to update through its owner; Base Dotfiles neither overwrites it nor publishes a second shadowing command.
- Preserve staged candidate preparation, fresh no-clobber publication, authorized-upgrade destination revalidation, atomic replacement or distribution switching, final health checks, and retained-state diagnostics.
- Lazygit retains single-member archive validation and executable-mode publication. Its same-release `checksums.txt` is no longer required at runtime once the reviewed per-platform digests are stored with the pin.
- Neovim retains safe archive member validation, prohibition of archive links, complete distribution publication, packaged-runtime validation, command-link ownership checks, and final runtime health validation. Because the selected Neovim Release does not publish separate checksum assets for these archives, preserve the reviewed GitHub asset digests as pinned release data.
- The production implementation must have no direct `api.github.com` dependency for chezmoi, Lazygit, or Neovim. Test fixtures may model forbidden calls to prove this invariant but must not make live network requests in routine tests.
- Do not add a user-facing version flag, mutable local Tool Lock, automatic pin refresh, or generic package-management framework. The existing tool-specific modules remain the appropriate seams.
- Preserve Feature Selection and execution ordering. Chezmoi remains prerequisite work; Lazygit and Neovim preparation occurs only for selected Features after confirmation and before managed configuration effects.
- Pinning Neovim refers to the editor distribution only. The existing lazy.nvim bootstrap, moving plugin declarations, plugin synchronization, Tool-managed State, and post-configuration readiness checks remain unchanged.
- Pinning Lazygit does not change its managed alias or claim ownership of Lazygit configuration, cache, logs, or repository state.
- Pinning these three tools does not change fnm's official installer/Homebrew routes, Herdr's stable manifest and native updater, shell package/update routes, Antidote behavior, source acquisition, or the top-level Base Dotfiles latest-Release URL.
- Update user documentation so that it describes fixed supported baselines and reviewed artifact verification instead of claiming that these three tools are resolved to the latest stable release on every invocation.
- Record that this specification supersedes the earlier no-pin/current-target decisions for chezmoi, Lazygit, and the Neovim editor distribution. The earlier migration specification and completed tickets remain historical records; their unrelated ownership, safety, configuration, and verification decisions continue to apply.
- The generated installer must inline the fixed chezmoi policy and remain pinned to the Base Dotfiles source revision represented by its Release. Source and generated installer behavior must agree.

## Testing Decisions

- Use the public installer entrypoint as the primary acceptance seam. Exercise it with disposable HOME, source, config, state, and destination directories, controlled command fixtures, and no writes to the developer's real environment.
- Retain direct `chezmoi apply` as the second existing public seam for selected Feature scripts. It is already a supported path and catches differences between installer orchestration and rendered chezmoi execution; no new user-facing test seam is needed.
- Good tests assert observable outcomes: exit status, requested network URLs, installed version, artifact identity, executable health, retained previous installation, managed configuration, backups, and absence of unintended calls. They must not assert private helper names or incidental decomposition.
- Add a regression in which any request to `api.github.com` fails immediately, then prove that compatible chezmoi bootstrap and successful pinned Lazygit/Neovim preparation do not attempt such a request.
- Verify that an already-compatible chezmoi makes no release metadata, archive, or checksum request and proceeds through source acquisition.
- Verify missing and older authorized chezmoi cases select exactly `2.72.1`, verify the matching pinned digest, preserve no-clobber and replacement-race behavior, and work through both source and generated release installers.
- Cover chezmoi platform and architecture mapping, including the applicable Linux libc route, with controlled fixtures. No test may download or replace the developer's real chezmoi.
- Verify Lazygit missing and older authorized-direct cases request only the exact `0.65.1` platform archive, validate its pinned digest and member layout, and publish a healthy command before applying the alias.
- Verify Lazygit equal and newer stable cases make no release request and retain the existing executable bytes. Verify an older external owner is rejected without shadow installation.
- Verify Neovim missing and older authorized-direct cases request only the exact `0.12.5` platform archive, validate the pinned digest and safe complete runtime, and publish the distribution before configuration.
- Verify Neovim equal and newer stable cases make no editor release request and retain the existing distribution or external executable. Plugin synchronization remains expected after configuration and is tested separately from editor-archive traffic.
- Test all four declared Lazygit and Neovim OS/architecture routes. Each route must use the exact reviewed asset name and digest.
- Test checksum mismatch, malformed archive, unsafe member, extraction failure, candidate version mismatch, candidate health failure, destination appearance, authorized-upgrade race, publication failure, and final health failure. Preserve the existing usable installation whenever failure occurs before activation.
- Replace tests that expect a metadata failure to be fatal with tests that make release metadata unavailable and prove it is never requested.
- Replace tests that publish a synthetic newer upstream target and expect automatic adoption with tests proving a newer upstream target does not change the pinned target. Pin changes are tested as repository changes, not as runtime discovery.
- Preserve cancellation, Preview, dry-run, unselected Feature, configuration-before/after failure, retry, backup, mode, alias, complete-runtime, plugin-sync, and combined-installation regressions.
- Extend release-pipeline verification to assert that the generated installer embeds the pinned chezmoi version and integrity mapping and that the released source contains the pinned Lazygit and Neovim targets.
- Add a production-source assertion that no direct GitHub REST API endpoint remains in the three pinned tool paths. Do not confuse ordinary versioned GitHub asset downloads or repository Git traffic with REST API calls.
- Routine automated tests use controlled local release fixtures and must not depend on the live current release. A separately invoked maintenance check may compare pins and hashes with upstream, but it cannot change runtime behavior or gate ordinary installation on API availability.
- Reuse the established installer, tool-specific, combined-installation, integration, runtime, and release-pipeline suites as prior art. Update assertions that deliberately encode the superseded moving-target policy while retaining unrelated safety coverage.

## Out of Scope

- Automatically updating any of the three pins at runtime.
- Adding GitHub credentials, tokens, API authentication, proxy rotation, rate-limit retries, or a cache of latest-release metadata.
- Pinning or redesigning fnm, Herdr, Zsh, Homebrew, APT, Antidote, or shell plugin update behavior.
- Pinning Neovim plugins, adopting or managing `lazy-lock.json`, or promising fully offline Neovim setup.
- Removing all network access from installation. Missing or older managed tools still require exact versioned asset downloads; source acquisition and selected native plugin/tool operations retain their documented network behavior.
- Changing the top-level command that selects the latest Base Dotfiles Release. That GitHub Release redirect is separate from the unauthenticated REST API quota involved in this incident.
- Adding a user-facing version selector, rollback command, downgrade path, central package manager, or broad tool-update command.
- Taking ownership of externally installed tools, deleting newer versions, or publishing shadow copies ahead of another Owner's command.
- Retroactively changing previously published Base Dotfiles Releases. The new policy takes effect only after implementation and publication of a new Release.

## Further Notes

- The fixed versions captured for this work are chezmoi `2.72.1`, Lazygit `0.65.1`, and Neovim `0.12.5`. Lazygit `0.65.1` was published on 2026-09-13 and Neovim `0.12.5` on 2026-08-23. Later upstream releases do not change this specification.
- Reviewed Lazygit `0.65.1` SHA-256 values are: Darwin arm64 `65a367c6ea9a88efebaaf7998a6835eedb987e04916cef677264ff9b31b1b13e`; Darwin x86_64 `fde13daf583511aa24c42ca154911643231a5af784c7cdd8117264b2fc035b33`; Linux arm64 `49abecdf6adf4f2dfdb11bf7b9bfada267ea523612ed809d1c6d87f6c04000a7`; Linux x86_64 `02beacbcda0fa342e50ae3480ba8147307353af3fb28e1d5f790e02329c201a6`.
- Reviewed Neovim `0.12.5` SHA-256 values are: Linux arm64 `1aa5ca085249580ae0f91eb14f27ec0919773ff2d99a163d03f3d6c21ac29725`; Linux x86_64 `bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875`; macOS arm64 `65fb000099e47ca1b762584c484cc833f40e30851a0ec450d4174e16317c1f9b`; macOS x86_64 `81f4518622cb059b450ee2e498c6a1082a222f6bd89589de5bbcf0c6a68aa3fd`.
- Reviewed chezmoi `2.72.1` SHA-256 values are: Darwin arm64 `938d422091cc001e68fe3fd7efea9b923a36facbf2b8db67063639abbaf72de2`; Darwin amd64 `bf0f0e048291efe126cb8bc51cf566057b92755cd53ce82c45efa11d2f8f4898`; Linux arm64 `75508ef41216b6d64f3145986b751729d7f92d09c6bad77d51cf2895ab35a508`; Linux amd64/glibc amd64 `9f97d32caca166e5c92160ec3a9325519809c38963121cef38173142065c981f`; Linux musl amd64 `b961e2972d6fcd1002f9b986d4a61dc5da288e96aab226434fd5b20a7de80cf9`.
- These digests and assets share the same upstream GitHub Release trust boundary. They provide deterministic integrity checking against reviewed repository data, not an independent authenticity signature.
- The original incident's proxy returned different GitHub rate-limit buckets on successive requests, while direct access retained most of its quota. Fixed release inputs remove this nondeterministic API dependency rather than trying to predict which shared proxy exit a Workstation will receive.
- A new Base Dotfiles Release is required after implementation. Updating only the source branch does not change the already-published installer downloaded by the documented one-line command.
