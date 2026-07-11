# Plasticine CLI Workstation Bootstrap

Status: ready-for-agent

## Problem Statement

The Owner needs to keep one strongly opinionated terminal environment consistent across personal macOS and Linux Workstations. The current repository relies on a mutable checkout and a legacy Bash installer that performs configuration directly, resolves moving tool versions, scatters state across conventional directories, and has no complete Plan, durable ownership model, safe Conflict handling, component-level crash recovery, or bounded rollback. A fresh Workstation still requires several unrelated manual steps, and Linux terminal sessions repeatedly lose GitHub SSH authentication.

The same repository is also used on company Workstations where personal Git and GitHub SSH configuration must be excluded non-interactively without preventing unrelated tools from using Git as a System Dependency. The Owner therefore needs one versioned, testable, repeatable CLI that can be obtained with a single curl pipe, requires no Go installation on the target Workstation, makes all intended mutations visible before execution, and converges safely on every later run.

## Solution

Publish a minimal POSIX Bootstrap that selects an immutable Release, verifies the raw Go binary for the Workstation's Artifact Target, and hands installation plus first Apply to that candidate Workstation CLI. The plasticine CLI exposes only plan, apply, doctor, and version. A concrete Reconciler owns the embedded Desired State, Tool Lock, Component graph, Workstation Scope, Reconciliation State, Conflict resolution, Retirement, and narrowly authorized System Changes.

Every Release freezes the CLI and handwritten non-secret configuration together. All persistent locations associated with Plasticine are centralized under the Owner-only ~/.plasticine Plasticine Home, divided conceptually into binaries, versioned Managed Tools, managed configuration, Reconciliation State and backups, artifact cache, and relocated runtime content. Runtime contents remain Tool-managed State outside Reconciliation ownership, drift, and backup. Outside Plasticine Home, only the materialized Zsh and Git shims plus the SSH Managed Block remain at conventional locations; Neovim is entered through its stable launcher.

The initial Components are shell, git-config, github-ssh, neovim, lazygit, fnm, and uv. Managed Tools are installed at exact Tool Lock versions from verified user-scoped artifacts, while Git, Zsh, OpenSSH, and CA capabilities remain System Dependencies owned by the operating system. GitHub SSH is configured only on the Workstation from an Owner-supplied private-key reference; public-key registration remains manual, macOS uses native Keychain behavior, and supported Linux uses one shared user-level systemd ssh-agent.

## User Stories

### Bootstrap and installation

1. As an Owner, I want to install Plasticine on a fresh Workstation with `curl -fsSL <url> | sh`, so that I can bootstrap a machine without cloning the repository first.
2. As an Owner, I want Bootstrap to install a directly executable binary for my Workstation's operating system and architecture, so that the Workstation does not need Go or another language runtime.
3. As an Owner, I want the fixed Bootstrap URL to select the latest stable Release by default, so that an ordinary installation never consumes an unpublished branch or implicit prerelease.
4. As an Owner, I want to select an exact Release with PLASTICINE_VERSION, so that I can reproduce an installation or request a bounded rollback.
5. As an Owner, I want each selected Release to contain one immutable pairing of the CLI and its non-secret Desired State, so that repeating the same version does not depend on the current repository checkout.
6. As an Owner, I want Bootstrap to verify the downloaded CLI against the Release checksum before execution, so that corrupted or mismatched artifacts fail before installation.
7. As an Owner, I want Bootstrap itself to remain user-scoped and never invoke sudo, so that piping it from the network does not create a privileged shell installer.
8. As an Owner, I want Bootstrap to contain only target detection, download, verification, and candidate handoff, so that the network-executed shell remains small and auditable.
9. As an Owner, I want the candidate CLI to validate state compatibility and atomically replace the installed CLI, so that an interrupted or incompatible installation preserves the previously working executable.
10. As an Owner, I want installation to refuse to overwrite an executable that cannot identify itself as a compatible Plasticine CLI, so that an unrelated file at the target path is never silently destroyed.
11. As an Owner, I want Bootstrap arguments such as --exclude, --github-key, --yes, --allow-system, and --adopt to reach the first Apply, so that unattended and machine-specific initialization can be expressed in the original command.
12. As an Owner, I want a successfully installed candidate CLI to remain installed even when its first Apply is denied, partial, or failed, so that I can diagnose and resume without rerunning Bootstrap.

### CLI and Plan

13. As an Owner, I want the initial public command surface limited to plan, apply, doctor, and version, so that there is one clear path for each supported operation.
14. As an Owner, I want version to identify the Release or development build, commit, and relevant build metadata, so that I can tell exactly which CLI and Desired State I am running.
15. As an Owner, I want concise human-readable output with TTY-only color that honors NO_COLOR, so that output remains legible both interactively and in logs.
16. As an Owner, I want stable exit statuses for success, operational failure, usage error, and interruption, so that scripts can distinguish those outcomes without a JSON contract.
17. As an Owner, I want plan to discover the complete set of changes, Conflicts, blockers, Scope changes, state migrations, System Changes, and Retirements without mutation, so that I can understand the entire run before authorizing it.
18. As an Owner, I want plan to remain offline, so that inspecting Workstation drift never depends on network availability or produces network side effects.
19. As an Owner, I want a successfully computed Plan to exit successfully even when it contains changes, so that changes required is not confused with planning failed.
20. As an Owner, I want any planning failure to leave both filesystem and Reconciliation State unchanged, so that incomplete discovery can never partially initialize the Workstation.

### Apply, safety, and recovery

21. As an Owner, I want the same apply operation to initialize an empty Workstation and reconcile every later run, so that first-use behavior cannot diverge from repeat behavior.
22. As an Owner, I want repeated Apply runs against an already converged Workstation to be safe and produce no unnecessary mutations, so that Reconciliation is genuinely repeatable.
23. As an Owner, I want Apply to construct a complete immutable Plan, present it once, and execute that exact Plan after authorization, so that it does not discover surprising work while mutating.
24. As an Owner, I want interactive Apply confirmation to use the terminal even when invoked through a curl pipe, so that Bootstrap input and authorization do not interfere.
25. As an Owner, I want non-interactive Apply to require explicit --yes, so that the absence of a TTY never grants mutation authority implicitly.
26. As an Owner, I want every Plan containing System Changes to require --allow-system in addition to ordinary confirmation, so that user-scoped and system-scoped authority remain distinct.
27. As an Owner, I want Plasticine to elevate only the concrete system subprocess that needs privilege, so that neither the CLI nor user-scoped Reconciliation runs as root.
28. As an Owner, I want a failed Component to skip only its dependents while independent Components continue, so that one failure does not discard useful convergence elsewhere.
29. As an Owner, I want each Component's effects to be atomic where possible and verified before ownership is committed, so that partial writes are not recorded as successful Reconciliation.
30. As an Owner, I want concurrent Plan and Doctor runs to coexist while Apply and CLI replacement receive exclusive access, so that Plasticine processes cannot corrupt shared state.
31. As an Owner, I want lock contention to fail quickly with holder information, so that I can identify the competing Plasticine process instead of waiting indefinitely.
32. As an Owner, I want every mutation to recheck the precondition observed by its Plan, so that an external edit made after planning becomes a stale-Plan error rather than being overwritten.
33. As an Owner, I want an interrupted Component recorded in a Secret-free pending journal, so that the next Apply can finalize proven effects or safely resume idempotent work.
34. As an Owner, I want ambiguous interrupted effects to become blockers and package-manager effects to be re-observed rather than rolled back blindly, so that crash recovery reflects actual Workstation state.
35. As an Owner, I want state schema migrations shown in Plan and persisted only by authorized Apply, so that upgrading local metadata remains observable and follows the same mutation rules.
36. As an Owner, I want corrupted state or a schema newer than the running CLI understands to block without writes, so that an older or incompatible binary cannot damage Reconciliation State.
37. As an Owner, I want loss of Reconciliation State to make existing content a Conflict rather than recreating ownership by guesswork, so that Plasticine never assumes it owns unknown files.

### Workstation Scope and Components

38. As an Owner, I want one Release-defined Desired State with platform branches rather than arbitrary profiles or machine-local value overrides, so that my Workstations share one understandable configuration source.
39. As an Owner, I want a persistent exclusion-only Workstation Scope, so that company machines can disable personal Components without introducing a second configuration language.
40. As an Owner, I want --exclude to replace the complete persisted exclusion set, so that non-interactive initialization can deterministically declare a Workstation's Scope.
41. As an Owner, I want plain Plan and Apply to reuse the persisted Workstation Scope, so that I do not have to repeat exclusions on every run.
42. As an Owner, I want Components introduced by a future Release to be enabled unless explicitly excluded, so that new personal configuration reaches my ordinary Workstations automatically.
43. As an Owner, I want --component to narrow one Plan or Apply without changing persisted Scope or enabling an excluded Component, so that I can diagnose and retry a subset without redefining the machine.
44. As an Owner, I want invalid Component dependency selections to block before mutation, so that selecting github-ssh or fnm without their required shell Component cannot create a broken partial configuration.
45. As an Owner, I want enabled Components to derive non-excludable System Dependencies independently of personal configuration, so that excluding personal Git settings does not suppress Git software required by another Component.
46. As an Owner, I want an excluded previously managed Component to become Suspended without inspection, deletion, or ownership loss, so that I can later re-enable it exactly where Reconciliation left it.
47. As an Owner, I want a changed Workstation Scope persisted before Component effects after all blockers and authorization pass, so that a partial Apply still preserves my intended blacklist.
48. As an Owner, I want the initial stable Components to be shell, git-config, github-ssh, neovim, lazygit, fnm, and uv, so that module selection uses stable, documented identifiers.

### Conflict, adoption, and backup

49. As an Owner, I want unmanaged differing content and Owner drift on a Managed Path to become Conflicts, so that Plasticine never silently overwrites, merges, or deletes my edits.
50. As an Owner, I want --adopt to authorize every adoptable Conflict visible in the current filtered Plan, so that adoption remains explicit without creating a per-path selection language.
51. As an Owner, I want non-interactive adoption to require both --adopt and --yes, so that unattended runs cannot infer destructive consent.
52. As an Owner, I want every adopted path or overwritten Owner drift backed up to a unique immutable location with source metadata, so that repeated runs never overwrite an ambiguous fixed .bak file.
53. As an Owner, I want ordinary Release updates to avoid backups when current content still matches the last accepted Desired State, so that backups represent human content at risk rather than routine generated versions.
54. As an Owner, I want backups retained indefinitely as ordinary local files under Owner-only state storage, so that I can inspect and restore them manually without a hidden retention policy.
55. As an Owner, I want Secret targets excluded from adoption and backup under all circumstances, so that a private key never enters Plasticine-managed storage.
56. As an Owner, I want the GitHub SSH Include to be the sole Managed Block inside an otherwise Owner-controlled file, so that Plasticine can integrate with ~/.ssh/config while preserving all bytes outside its markers.
57. As an Owner, I want first insertion of the SSH Managed Block into an existing file to require adoption and a whole-file backup, so that even the exceptional merge case remains explicitly authorized.
58. As an Owner, I want missing, duplicate, or malformed SSH markers to block rather than trigger a guessed repair, so that Plasticine never edits an ambiguous Owner-controlled file.

### GitHub SSH and Git

59. As an Owner, I want to provide my GitHub private-key path interactively or with --github-key when the Component is first enabled, so that Plasticine configures the key I chose instead of scanning or guessing.
60. As an Owner, I want Plasticine to validate that the selected key is a current-user-owned regular file with restrictive permissions, readable key material, and a stable public fingerprint, so that unsafe or substituted keys block locally.
61. As an Owner, I want Plasticine to persist only the normalized key path and public fingerprint as a Secret Reference, so that later non-interactive Apply runs can reuse my choice without storing the private key or passphrase.
62. As an Owner, I want a missing key, changed fingerprint, or unsafe permission to require an explicit new selection rather than automatic repair, so that control of the external Secret remains mine.
63. As an Owner, I want Plasticine to configure GitHub SSH only on the Workstation and leave public-key registration on GitHub to me, so that the CLI never needs remote account-write authority.
64. As an Owner, I want Releases to embed GitHub's official SSH host keys and use a dedicated managed known-hosts file, so that connections neither use ssh-keyscan nor trust a host on first use.
65. As an Owner, I want an old Release to fail closed when GitHub rotates host keys, so that host trust changes require an intentional new Release rather than silent acceptance.
66. As an Owner, I want macOS GitHub SSH to use native Keychain and agent integration, so that an encrypted key behaves consistently with the platform.
67. As an Owner, I want supported Linux Workstations to share one user-level systemd ssh-agent at a fixed socket and add my key only when its fingerprint is absent, so that every terminal shares authentication without repeated eval setup.
68. As an Owner, I want git-config to own my complete centralized personal Git configuration and only a minimal include shim at the conventional path, so that there is one personal Git source of truth.
69. As an Owner, I want the personal Git Desired State to omit plaintext credential storage, so that Plasticine does not reintroduce the obsolete credential.helper = store behavior.
70. As an Owner, I want GitHub HTTPS URLs rewritten to SSH only when both git-config and github-ssh are active, so that transport configuration cannot leak into a Workstation where either half is excluded.
71. As an Owner, I want excluding git-config to prevent Plasticine from reading, backing up, or modifying company-controlled Git configuration, so that company machines can retain an entirely separate Git policy.

### Shell, Managed Tools, and Plasticine Home

72. As an Owner, I want the shell Component to install or validate Zsh, place Plasticine launch entries on PATH, and select Zsh as my login shell, so that a fresh terminal receives the intended command environment.
73. As an Owner, I want a required chsh to be planned as an authorized System Change that takes effect only in a later terminal, so that Apply never replaces or mutates its own running shell process.
74. As an Owner, I want exact Release-pinned Neovim, Lazygit, fnm, and uv binaries installed from checksum-verified official artifacts without sudo, so that tool versions are reproducible without depending on native package versions.
75. As an Owner, I want Managed Tool payloads installed in versioned user directories with stable launch entries, so that version switches are atomic and callers do not depend on changing payload paths.
76. As an Owner, I want Neovim, fnm, uv, and uvx launchers to relocate their supported runtime directories, and Lazygit plus lg to use stable symlinks, so that direct and non-Zsh callers receive the same centralized behavior.
77. As an Owner, I want all persistent locations associated with Plasticine centralized beneath an Owner-only ~/.plasticine, so that binaries, tools, configuration, state, backups, cache, and relocated runtime data are not scattered across unrelated roots.
78. As an Owner, I want only the unavoidable Zsh and Git shims plus the SSH Managed Block outside Plasticine Home while Neovim starts through its centralized launcher, so that managed configuration survives checkout removal without inventing a Neovim conventional-path shim.
79. As an Owner, I want artifact downloads cached by SHA-256, reverified on every hit, and promoted only after complete verification, so that repeated Apply runs can reuse trustworthy content after interrupted downloads.
80. As an Owner, I want conventional proxy environment variables honored without their potentially credential-bearing values appearing in output, so that managed downloads work on proxied networks without leaking secrets.
81. As an Owner, I want Managed Tool versions to change only through a reviewed, complete Tool Lock rather than runtime latest resolution or scheduled updates, so that no Workstation changes tool versions implicitly.
82. As an Owner, I want Zsh and Neovim plugins, fnm-managed Node versions, and uv-managed Python environments and tools to remain Tool-managed State, so that Plasticine reconciles configuration and core binaries without pretending to own their transitive ecosystems.
83. As an Owner, I want Tool-managed State relocated beneath Plasticine Home but excluded from Plan, drift checks, backup, and Release guarantees, so that storage is centralized without expanding Plasticine's ownership boundary.
84. As an Owner, I want my VS Code configuration retained as Reference Configuration for manual copying only, so that it remains available in the repository without becoming part of Release or Reconciliation.

### System Dependencies and platform support

85. As an Owner, I want Managed Tools pinned exactly while Git, Zsh, OpenSSH, and CA bundles remain capability-based System Dependencies, so that Plasticine can upgrade missing or insufficient system software without downgrading or pinning OS-owned packages.
86. As an Owner, I want Debian and Ubuntu Apply to aggregate missing packages into one apt-get update and one minimal install operation, so that system provisioning is efficient and avoids repeated privilege prompts.
87. As an Owner, I want Plasticine never to run a global apt upgrade, downgrade satisfied packages, or carry sudo credentials, so that System Changes remain narrow and native authentication stays under OS control.
88. As an Owner, I want a required sudo password without a usable TTY to fail explicitly, so that non-interactive Reconciliation never hangs or fabricates credentials.
89. As an Owner, I want missing Apple Command Line Tools to launch Apple's supported installer only after authorization and then report dependent Components as awaiting my action, so that I can complete the system dialog and rerun Apply safely.
90. As an Owner, I want Plasticine to avoid installing Homebrew or using unofficial silent Apple tooling as a prerequisite workaround, so that macOS system provisioning follows the platform-supported path.
91. As an Owner, I want full Reconciliation supported on macOS 13+, Debian 12+, and Ubuntu 22.04+ on amd64 and arm64, so that the promised platform boundary is explicit.
92. As an Owner, I want older supported-family releases and other compatible 64-bit Linux systems to allow best-effort binary and user-scoped actions while reporting unsupported System Changes, so that Plasticine does not guess foreign package-manager or service commands.
93. As an Owner, I want unsupported operating systems, architectures, and 32-bit machines rejected clearly, so that a missing Artifact Target is not mistaken for a transient download failure.

### Doctor, network, and privacy

94. As an Owner, I want doctor to check local Reconciliation health and run bounded HTTPS diagnostics, so that I can distinguish local drift from network reachability problems.
95. As an Owner, I want Doctor to run a non-interactive, no-write GitHub SSH authentication check only when github-ssh is active, so that I can verify actual authentication without prompts or remote mutations.
96. As an Owner, I want Doctor checks to continue independently after individual failures and return unhealthy when any required check fails, so that one problem does not hide the rest of the diagnosis.
97. As an Owner, I want Doctor never to mutate configuration, known hosts, remote accounts, or Reconciliation State, so that diagnosis is safe to run at any time.
98. As an Owner, I want Plasticine's direct network access limited to GitHub Release retrieval, Tool Lock artifact URLs, and bounded Doctor diagnostics, so that its egress is predictable and auditable.
99. As an Owner, I want no telemetry, analytics, crash upload, background update check, or network activity outside explicitly invoked Bootstrap, Apply, Doctor, System Change, and Tool-managed behavior, so that my Workstation behavior remains private and predictable.

### Retirement and version rollback

100. As an Owner, I want a selected Release to Plan explicit Retirement for owned resources of an active non-Suspended Component that no longer exist in its catalog, so that removed configuration is not silently orphaned.
101. As an Owner, I want Apply to remove unchanged retiring configuration, shims, launchers, and Managed Tool payloads and then release their ownership, so that obsolete Release-owned artifacts leave the Workstation cleanly.
102. As an Owner, I want drift on a retiring Managed Path to become a Conflict that is deleted only after --adopt creates a backup, so that Retirement cannot silently discard my edits.
103. As an Owner, I want Retirement never to uninstall System Dependencies or delete Tool-managed State, so that bounded cleanup does not destroy OS-owned or nested ecosystem data.
104. As an Owner, I want a Suspended Component whose catalog definition disappears to remain untouched while Doctor reports it, so that exclusion is never reinterpreted as consent to uninstall.
105. As an Owner, I want an explicitly selected older CLI to perform a read-only state compatibility check before replacing the installed version, so that an incompatible rollback leaves the current CLI intact.
106. As an Owner, I want a compatible older Release to restore its own configuration and exact Managed Tool versions through normal Plan, Conflict, and Retirement rules, so that rollback remains observable and safe.
107. As an Owner, I want rollback to leave System Dependencies and Tool-managed State at their current versions and contents, so that version selection is not misrepresented as a complete Workstation snapshot restore.

### Release and development workflow

108. As an Owner, I want each SemVer Release to publish raw binaries for macOS and Linux on amd64 and arm64 together with checksums.txt and install.sh, so that Bootstrap can remain dependency-light.
109. As an Owner, I want a vX.Y.Z tag to publish only after all four builds, checksums, Tool Lock validation, tests, and supported-platform smoke checks pass, so that incomplete Releases never become installable.
110. As an Owner, I want published tags and assets to remain immutable and prereleases to require explicit selection, so that an exact version continues to identify the same bytes.
111. As an Owner, I want Release builds to use a pinned Go toolchain and module graph with reproducible build settings and only source-derived metadata, so that tagged artifacts can be independently rebuilt.
112. As an Owner, I want a local development build to Plan and Apply its embedded working-tree Desired State while clearly reporting commit and dirty metadata, so that configuration changes can be tested without creating throwaway Releases.
113. As an Owner, I want development builds barred from the hidden self-install path, so that a local experiment cannot impersonate or replace a published Release.
114. As an Owner, I want the legacy installer, uninstallers, obsolete flags, checkout assumptions, and duplicated configuration sources removed entirely, so that the new CLI carries no compatibility debt or unsafe historical cleanup behavior.
115. As an Owner, I want an old repository checkout to remain a manual cleanup concern after successful new Apply, so that the CLI never performs an unsafe guessed deletion of historical directories.

## Implementation Decisions

### Product and module boundaries

- Plasticine is an Owner-specific Workstation reconciler, not a general-purpose dotfiles framework. It does not identify, reject, or adapt to other people who execute it.
- The Workstation CLI is written in Go and published as self-contained binaries for four Artifact Targets: macOS and Linux on amd64 and arm64. Target Workstations do not require Go.
- A Release is the immutable unit of CLI behavior, handwritten non-secret configuration, GitHub host keys, and Tool Lock data. Runtime never reads a repository checkout or moving branch.
- The public command surface is limited to plan, apply, doctor, and version. There is no separate initialization path; first use and later convergence both use Apply.
- Command handlers remain thin. One concrete Reconciler Module concentrates policy behind the highest business seam: Plan, Apply, and Doctor. Version reporting bypasses the Reconciler.
- The Reconciler does not expose a public Go interface or action DSL. Its closed action model and its filesystem, process, download, clock, platform, and state Adapters remain internal.
- Desired State and Component relationships are typed Go code. Handwritten configuration is embedded. Tool Lock is a checked, build-validated input. No YAML schema, template language, plugin mechanism, or machine-local value override is introduced.
- Secrets remain local inputs and never enter the repository, a Release, Desired State, Plan, Reconciliation State, pending journals, backups, or logs. Only non-sensitive Secret References may persist.

### Component and Scope model

- Stable initial Component IDs are shell, git-config, github-ssh, neovim, lazygit, fnm, and uv.
- github-ssh and fnm require shell. Enabled Components derive non-excludable Zsh, Git, OpenSSH, and CA System Dependencies as needed. Shell owns PATH integration.
- System Dependency derivation is fixed: shell derives Zsh, Git, and CA capabilities; git-config derives Git; github-ssh derives OpenSSH in addition to its shell Component dependency; neovim derives Git and CA capabilities; lazygit derives Git; fnm derives CA capabilities in addition to its shell Component dependency; and uv derives CA capabilities.
- If persistent Scope excludes shell while github-ssh or fnm remains active, Plan blocks. It does not silently re-enable shell or skip the invalid dependency.
- Workstation Scope is a persisted exclusion set. All non-excluded Components, including future Components, are enabled by default.
- The --exclude option replaces the complete intended exclusion set. Plan previews that replacement without writes; authorized Apply persists it after blockers pass and before Component effects. Partial failure does not roll it back.
- The --component option may narrow a Plan or Apply to active Components for diagnosis or retry. It is not persistent and cannot expand Workstation Scope.
- Excluding an already managed Component creates a Suspended Component. Reconciliation neither inspects nor changes its content, ownership, or backups until it is re-enabled.

### Bootstrap, installation, and release selection

- Bootstrap is a minimal POSIX shell program responsible only for stable or explicit Release selection, Artifact Target detection, raw candidate download, Release-checksum verification, executable permission, and candidate handoff. It never performs Workstation configuration or sudo.
- The default source is the latest stable GitHub Release. PLASTICINE_VERSION selects an exact version. Prereleases require explicit selection, and mutable branch content is never executed.
- Bootstrap forwards Apply-related options to a hidden candidate entry that is absent from public help.
- The hidden entry takes the exclusive Plasticine lock, validates state compatibility read-only, atomically self-installs, and invokes first Apply.
- Compatibility or installation failure preserves the existing CLI. Once atomic replacement succeeds, the new CLI remains installed even if first Apply is denied, partial, or failed.
- An existing executable that cannot identify itself as a compatible Plasticine CLI is never overwritten. Development builds cannot use the hidden self-install path.

### Plan, Apply, authorization, and outcomes

- Plan completes all read-only discovery before mutation. It describes changes, blockers, Conflicts, Scope changes, schema migrations, System Changes, component skips, and Retirements, and it never performs network I/O.
- Apply internally creates an immutable Plan, presents and authorizes it, and executes that exact value. It does not discover additional mutation work during execution.
- Interactive Apply uses the controlling terminal for prompts, including when stdin is a curl pipe. Non-interactive Apply requires --yes; CI never grants implicit permission.
- A Plan containing any System Change also requires --allow-system. Ordinary confirmation and System Change authorization are independent.
- Plasticine always starts as the ordinary user and elevates only the specific system subprocess that needs privilege.
- Component application is atomic where practical. A failed Component skips dependents while independent branches continue. There is no claimed global transaction or unreliable rollback of external package managers.
- Successful Plan returns 0 even when changes are present. Fully successful Apply and healthy Doctor return 0. Blocked, denied, partial, failed, and unhealthy outcomes return 1; usage errors return 2; interruption returns 130.
- Initial output is concise and human-readable. Color is TTY-only and honors NO_COLOR. Structured internal outcomes do not create a JSON compatibility contract.

### Reconciliation State and interruption safety

- Reconciliation State is versioned metadata recording ownership, the applied Release or development Desired State digest, backups, pending work, and Secret References. Observed Workstation state always remains the source of truth.
- Plan and Doctor hold shared locks. Apply and candidate replacement hold an exclusive lock for the full protected operation. Contention fails fast with holder PID and command information.
- Locks protect Plasticine processes but cannot protect against external edits, so every mutation rechecks its planned precondition digest and reports a stale Plan on mismatch.
- Each Component writes a Secret-free pending journal before its first mutation, verifies effects, then atomically commits ownership and clears the journal.
- A later Plan only reports interrupted work. A later Apply may finalize a provably complete effect or resume idempotent work; ambiguous effects block, and package-manager effects are re-observed rather than rolled back.
- State schema migrations are calculated in memory and shown by Plan. Apply persists them only after authorization. Corrupt, unknown, or newer schemas block without writes; older CLIs never downgrade state.
- If Reconciliation State is lost, every existing candidate Managed Path becomes a Conflict even when its bytes happen to match current Desired State. Plasticine never infers historical ownership from content equality.

### Conflict, backup, Managed Block, and Retirement

- A Conflict is content that cannot be preserved by the Plan and does not match the last content accepted by Reconciliation. It includes unmanaged differences, drift on continuing Managed Paths, and Retirement drift.
- --adopt authorizes every adoptable Conflict in the filtered Plan. Non-interactive adoption also requires --yes, and System Changes still require --allow-system.
- Adoption and Owner-drift replacement create unique immutable backups with source metadata. Normal Release updates whose current bytes match the last accepted bytes do not create backups.
- Backups remain local under Owner-only state storage and are never pruned automatically. The first version has no restore or prune command.
- Secret Reference targets can never be adopted, copied, or backed up. Opaque data inside an adopted configuration backup remains local and is never logged.
- The GitHub SSH include is the only initial Managed Block. Plasticine owns a complete central fragment and a stable marker block in the Owner-controlled SSH configuration, preserving every byte outside the markers.
- First insertion into an existing SSH configuration is a Conflict requiring adoption and a whole-file backup. Missing, duplicate, or malformed markers block guessed repair.
- A resource owned by an active, non-Suspended Component but absent from the selected Release catalog produces explicit Retirement. Omission caused only by a one-run --component filter never causes Retirement or any other mutation to the omitted Component. Unchanged retiring configuration, shims, launchers, and Managed Tool payloads may be deleted before ownership is released.
- Retirement drift becomes a Conflict and requires --adopt, backup, deletion, and ownership release. Retirement never uninstalls System Dependencies or deletes Tool-managed State.
- A Suspended Component is not retired. If its catalog definition disappears, it remains untouched and Doctor reports the orphaned suspension.
- Compatible rollback to an older Release uses the same Conflict and Retirement rules. It may restore managed configuration and exact Managed Tools, but never downgrades System Dependencies or Tool-managed State.

### Configuration, tools, and centralized runtime

- Plasticine Home is Owner-only with root mode 0700 and centralizes binaries, versioned tool payloads, managed configuration bodies, state, journals, locks, backups, artifact cache, and relocated Tool-managed State.
- Only unavoidable materialized integration shims remain at conventional locations. Managed configuration is atomically materialized and never linked to a repository checkout or extracted Release.
- Neovim, Lazygit, fnm, and uv are exact-version Managed Tools installed from immutable, checksum-verified Tool Lock artifacts without sudo.
- Managed Tool payloads live in versioned user-scoped locations behind stable launch entries. Old payloads may be removed only after a verified successful switch.
- Neovim, fnm, uv, and uvx use minimal launchers to set supported relocation variables before executing exact payloads. Lazygit and its lg alias use stable symlinks.
- Artifact downloads are cached by SHA-256, reverified on every hit, written through partial files, and promoted atomically only after verification.
- Conventional proxy environment variables are honored, but values that may contain credentials are redacted. Runtime never resolves latest, stable, or branch references for Managed Tools.
- Managed Tool versions change only through reviewed Tool Lock edits covering every Artifact Target. Helpers may compute candidate metadata but do not commit or publish automatically.
- Zsh and Neovim plugins and generated files, fnm's Node versions and aliases, and uv's Python versions, environments, and tools are Tool-managed State. Plasticine relocates supported runtime roots but does not Plan, inspect, back up, repair, or version their contents.
- Project-local environments and unavoidable operating-system runtime files retain their native locations.
- Only handwritten Git, Zsh, and Neovim configuration enters Desired State. Generated plugin loaders do not.
- VS Code files remain Reference Configuration for manual copying and never enter Release, Plan, ownership, or drift semantics.

### System Dependencies and platform behavior

- Git, Zsh, OpenSSH, and CA capabilities are System Dependencies checked by presence, minimum version, or required capability. They are never exact-pinned or downgraded.
- Debian and Ubuntu aggregate missing packages into one authorized package-index update and one minimal install. Plasticine performs no global upgrade, does not downgrade satisfied packages, and never transports sudo credentials.
- A non-interactive Linux run that needs a sudo password fails explicitly when no usable terminal exists.
- On macOS, missing Apple development tools are handled only through the official installer after System Change authorization. Dependent Components remain awaiting Owner action until the system dialog completes and Apply is rerun. Homebrew and unofficial silent installers are not used.
- Shell ensures Zsh is available and plans login-shell selection as an explicit chsh System Change. Apply never sources configuration into itself or replaces its current process.
- Full Reconciliation has Support Floors of macOS 13, Debian 12, and Ubuntu 22.04 on both amd64 and arm64.
- Other compatible 64-bit Linux systems and older releases may run binary and user-scoped behavior on a best-effort basis, but unsupported System Changes are reported rather than guessed.

### Git and GitHub SSH

- git-config owns the complete personal Git configuration plus a minimal include shim, with no local override fragment and no plaintext credential store.
- When git-config is excluded, Plasticine does not read, back up, or modify company-controlled Git configuration.
- GitHub HTTPS-to-SSH rewriting is composed only when git-config and github-ssh are both active.
- A GitHub private-key path is accepted only from an interactive prompt or --github-key when the Component is first enabled or its persisted Secret Reference is invalid. No standard key path is scanned or guessed.
- Key validation requires a current-user-owned regular file, restrictive permissions, ssh-keygen readability, and a public fingerprint. Plasticine does not chmod, copy, back up, or store the passphrase.
- Reconciliation persists only the normalized path and public fingerprint as a Secret Reference. Missing files, unsafe modes, or fingerprint changes block until the Owner explicitly chooses again.
- Plasticine configures only the local Workstation. GitHub public-key registration remains manual.
- Releases embed GitHub's official SSH host keys in a dedicated managed known-hosts input. Plasticine never uses ssh-keyscan or trust-on-first-use, and an old Release fails closed after key rotation.
- macOS uses native Keychain and AddKeysToAgent behavior.
- Supported Linux uses one user-level systemd ssh-agent at a fixed shared socket. Managed shells export that socket, and ssh-add runs only when the configured fingerprint is absent.

### Doctor, networking, development, and publication

- Doctor combines local health checks with short-timeout HTTPS diagnostics. When github-ssh is active, it also performs a BatchMode GitHub SSH authentication check.
- Doctor never prompts, mutates known hosts or local state, or writes remotely. Individual checks continue after failure, and any required unhealthy check affects the final outcome.
- Bootstrap directly accesses GitHub Releases. Plasticine's own Apply HTTP client accesses only Tool Lock artifact URLs. Doctor performs only its bounded diagnostics.
- Explicitly authorized apt and Apple installer subprocesses may use system-configured sources, and Tool-managed ecosystems retain their own network behavior.
- Plasticine performs no telemetry, analytics, crash upload, background update check, or implicit scheduled work.
- Local development builds may Plan and Apply their embedded Desired State, report development commit and dirty metadata, and identify applied state by digest rather than pretending to be SemVer.
- SemVer tags drive Release production. All tests and assets complete before a draft is published; stable and prerelease selection remain distinct; published tags and assets are immutable.
- Releases contain four raw CLI binaries, checksums.txt, and the minimal install.sh without archive wrapping.
- Reproducible builds pin the Go toolchain and module graph, disable CGO, trim build paths, use source-derived tag, commit, and commit time metadata, and do not use UPX.
- The repository performs a complete cutover. Legacy installers, uninstallers, flags, checkout assumptions, obsolete documentation, and duplicate configuration sources are removed rather than supported through compatibility code.

## Testing Decisions

- Tests assert externally observable behavior and durable outcomes rather than private action ordering, helper functions, concrete Adapter types, or internal data layout.
- The primary and highest test seam is the concrete Reconciler's Plan, Apply, and Doctor methods. Most policy combinations enter through these methods and assert structured outcomes, state transitions, filesystem or process effects, and failure classification.
- Version, argument parsing, TTY behavior, color behavior, and exit-code mapping receive thin CLI contract tests. Business-policy scenarios are not duplicated at the command layer.
- Deterministic Adapters model platforms, filesystems, subprocesses, downloads, clocks, locks, and injected failures without reading or changing the developer's real Workstation.
- A smaller integration suite uses an isolated temporary HOME and the real filesystem to cover permissions, atomic replacement, launchers and symlinks, byte-preserving Managed Blocks, backups, locks, and state persistence.
- Plan tests cover offline operation, zero mutation, the complete blocker set, Scope previews, Component narrowing, System Change classification, schema-migration display, Retirement display, and planning-failure zero-write guarantees.
- Apply tests prove that the internally generated immutable Plan is the one executed. They cover interactive confirmation, --yes, independent --allow-system authorization, no-TTY denial, first and later runs, and stale precondition rejection.
- Every major success scenario runs Apply at least twice: the first run converges and the second observes no change or repeated side effect.
- Component tests cover graph validation, dependency order, downstream skip, independent-branch continuation, component-level verification, partial failure, exit classification, and successful rerun.
- Scope tests cover exclusion-set replacement, future Components defaulting active, Plan remaining read-only, Apply persistence before Component effects, persistence through partial failure, --component narrowing, and complete non-observation of Suspended Components.
- Conflict tests cover unmanaged differences, continuing Managed Path drift, Retirement drift, refusal without --adopt, all-Conflict adoption within a filtered Plan, non-interactive authorization combinations, and Secret Reference non-adoptability.
- Backup tests cover uniqueness, source metadata, permissions, creation for adoption or Owner drift, omission on clean Release updates, indefinite preservation, byte-for-byte preservation of opaque content while Plan, output, and logs do not expose it, and the prohibition on Secret copies.
- Managed Block tests cover absent files, empty files, first insertion into existing content, exact preservation outside markers, whole-file adoption backup, and missing, duplicate, or malformed marker blockers.
- Retirement tests cover clean deletion and ownership release, drift conversion to Conflict, adoption-backed deletion, one-run --component omission causing no Retirement, preservation of System Dependencies and Tool-managed State, orphaned Suspended Component warnings, and rollback through the same rules.
- State tests cover first-run state, lost state without guessed ownership, in-memory schema migration, authorized atomic persistence, corrupt and unknown schemas, newer-schema blocking, and refusal to downgrade state.
- Journal tests inject failure before and after each important Component effect. They verify journal-before-mutation, verify-before-commit, completed-effect finalization, idempotent resume, ambiguous-effect blockers, package-manager re-observation, and absence of Secrets.
- Lock tests cover concurrent shared Plan and Doctor, exclusive Apply and candidate replacement, fast contention failure with holder information, and stale digests after external edits. Targeted subprocess tests exercise real process locking.
- Bootstrap receives POSIX shell syntax checks and ShellCheck. Local HTTP fixtures test stable and exact version selection, all Artifact Target mappings, unsupported targets, checksum mismatch, interrupted downloads, and exact candidate argument forwarding.
- Candidate-handoff integration tests cover lock acquisition, compatible atomic replacement, incompatible state preserving the current CLI, unknown target executables, installation failure, and retention of the new CLI after first Apply is denied, partial, or failed.
- Managed Tool tests cover complete Tool Lock target data, exact artifact selection, checksum mismatch, version switching, launcher and symlink behavior, safe old-payload cleanup, and isolation of download failures to dependent Components.
- Artifact-cache tests use local HTTP fixtures for initial download, verified hits, corrupt-hit replacement, partial-file non-promotion, proxy redaction, timeouts, and enforcement of Tool Lock-only direct Apply HTTP.
- System Dependency tests use scripted process Adapters for capability discovery, no downgrade, Debian and Ubuntu batching, no global upgrade, sudo without a TTY, Apple installer waiting state, and authorized chsh. Ordinary CI never executes real sudo, apt, systemd, chsh, or system installers.
- Platform tests cover the four Artifact Targets, declared Support Floors through deterministic policy tests, representative current native systems, other Linux user-scoped best effort, and explicit unsupported System Changes.
- Git tests cover full personal ownership, total non-observation under company Scope, conditional SSH URL rewriting, and removal of plaintext credential storage from Desired State.
- SSH tests cover explicit key selection, persisted Secret Reference reuse, owner/type/mode/fingerprint validation, changed-fingerprint blockers, macOS Keychain arguments, one Linux agent and socket, conditional ssh-add, embedded GitHub host keys, and prohibition of ssh-keyscan.
- Doctor tests cover bounded timeouts, independent continuation, conditional SSH diagnostics, BatchMode, no prompts, no known-host mutation, no remote writes, and network failure affecting Doctor without contaminating Plan.
- CLI-output tests cover TTY and non-TTY output, NO_COLOR, exit statuses 0, 1, 2, and 130, and the absence of a promised JSON schema.
- Development-build tests cover commit and dirty identity, Desired State digest recording, allowed Plan and Apply, hidden self-install rejection, and later convergence by a stable Release.
- Release gates include all Go tests, isolated-home integration tests, Bootstrap validation, complete Tool Lock validation, four-target builds, checksum generation, tag and version consistency, and native macOS and Linux smoke tests. Any failure prevents publication.
- Native smoke tests exercise startup, version reporting, and safe read-only or user-scoped paths. They do not mutate the host's real system configuration.
- The repository has no prior Go or CI test suite to extend. This Reconciler-first structure becomes the baseline; the legacy shell installer is not treated as testing prior art.

## Out of Scope

- A general-purpose or team-oriented dotfiles product, user identity checks, execution denial for other users, or adaptation of Desired State to another person.
- Windows, WSL2, 32-bit targets, and architectures outside amd64 and arm64.
- Full package-manager or service support for Linux distributions other than Debian and Ubuntu.
- Clash, proxy-utils, proxy-service configuration, or their former scripts and binary assets.
- Anthropic or Claude configuration, environment variables, integrations, or Git-history rewriting for the historical fake or empty token.
- Automated VS Code installation or Reconciliation; VS Code remains Reference Configuration for manual copying.
- Profiles, allowlist-based Scope, interactive Component selection, arbitrary machine-local value overrides, a user-facing DSL, or a plugin API.
- Public-key registration with GitHub, remote account mutation, Secret distribution or synchronization, private-key copying or backup, private-key permission repair, or passphrase storage through a new keyring integration.
- Nerd Font installation.
- Homebrew installation or management.
- Exact pinning, downgrading, globally upgrading, or uninstalling System Dependencies.
- Ownership, pinning, backup, repair, or drift management for Zsh or Neovim plugins, generated loaders, Node versions and aliases, Python versions, virtual environments, or uv-installed tools.
- Automatic restore or pruning of backups. Backups are ordinary files restored or deleted manually in the first version.
- init, status, self-update, uninstall, cache-management, offline-bundle, or other additional public commands.
- Machine-readable JSON output or a public internal-action schema.
- Telemetry, analytics, crash upload, background update checks, scheduled tool updates, or runtime latest-version resolution.
- GPG, minisign, cosign, or another additional artifact-signature system in the first version.
- A global transactional rollback, rollback of System Dependencies, or rollback of Tool-managed State.
- Automatic migration, detection, removal, or compatibility behavior for a historical repository checkout. The Owner cleans it up manually after successful new Apply.

## Further Notes

- This spec synthesizes the accepted target design. The domain glossary defines canonical terms, and the non-superseded ADRs retain the rationale and take precedence if this summary is ambiguous.
- The accepted testing seam was already confirmed during design: Reconciler Plan, Apply, and Doctor are the single highest policy seam. No additional interview is required before implementation planning.
- The current repository has not implemented the Go CLI. The current worktree has no Go module, Go source, Tool Lock, release workflow, CI workflow, or generated four-target binary set.
- The current root documentation and install script still represent the legacy checkout-based Bash flow. Implementation must replace them completely rather than treating them as a partial Bootstrap.
- Legacy Git, Zsh, Neovim, and Lazygit content still exists. Cutover moves only handwritten configuration into embedded Desired State; old installers, uninstallers, generated plugin loaders, obsolete instructions, and duplicate sources are deleted.
- The current personal Git source still contains plaintext credential-helper configuration. The new Desired State must omit it; this spec does not claim it is already gone.
- VS Code Reference Configuration has been moved in the current dirty worktree but is not yet committed. Repository-local editor settings, if any, remain distinct from Owner reference material.
- The current dirty worktree also contains the accepted deletion of .env, Clash, WSL2 and proxy-utils material, and Anthropic or Claude content, together with untracked domain and agent documentation. These are preparation changes, not an implemented Release.
- Exact initial Managed Tool versions, immutable URLs, archive formats, and SHA-256 values are implementation-time Tool Lock inputs. They must cover all Artifact Targets and pass Release validation.
- Exact System Dependency capability thresholds, timeout durations, state field layout, SSH marker text and insertion position, and platform command details may use conventional engineering defaults as long as they preserve this spec's observable behavior and ADR constraints.
- Bootstrap download occurs before the candidate acquires the Plasticine lock. The hidden Go candidate holds the exclusive lock from state compatibility checking through self-installation and first Apply.
- A successfully installed compatible candidate remains installed after first Apply failure. A compatibility or installation failure preserves the prior CLI.
- Suspended Components and Retired resources are deliberately different: persistent exclusion never implies deletion, while Retirement applies only to active owned resources absent from the selected Release catalog. A one-run --component filter never creates either suspension or Retirement.
- The full platform promise is four Artifact Targets plus Support Floors of macOS 13, Debian 12, and Ubuntu 22.04. It must not be generalized to full support for every macOS or Linux environment.
