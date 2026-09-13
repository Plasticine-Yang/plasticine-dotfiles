# 14: Migrate independent fnm installation and updates

**What to build:** Let the Owner select fnm independently and obtain the current manager on every apply: the latest available Homebrew formula on macOS and the official script route on Linux. Preserve the existing shell activation and all Node versions, defaults, and native runtime data.

**Blocked by:** 07 — Separate tool preparation from configuration effects.

**Status:** done

- [ ] Add fnm to interactive and explicit non-interactive Feature Selection. It works alone and in combination with existing Features without implicitly selecting shell or depending on ticket 11's shell-update behavior.
- [ ] Every selected apply establishes the current permitted target and distinguishes missing, outdated, current, unhealthy, prerelease/custom, and unsupported-owner installations. An already-current installation avoids unnecessary executable replacement; health without a currency check is insufficient.
- [ ] On macOS, refresh Homebrew metadata and install or update only the fnm formula as necessary. Describe currency as the latest available formula, not a guarantee that Homebrew has published the newest upstream release already.
- [ ] Reuse the existing reviewed Homebrew bootstrap behavior when Homebrew is missing, without invoking unrelated shell probes or configuration. Show network, native terminal, administrator credential, and platform prerequisite effects before selected-feature confirmation; never synthesize native credentials.
- [ ] On Linux, use the official fnm installer with shell-file editing disabled and an explicit candidate destination. Download it completely before execution, do not pass a fixed release selector, and do not invoke a package-manager fallback.
- [ ] Stage and health-check script-route candidates before publishing them. Preserve fresh no-clobber behavior, distinguish authorized direct upgrades from creation, revalidate destinations, and preserve a working installation when preparation fails.
- [ ] Verify the resulting manager against the resolved current target. Metadata, script, native package-manager, publication, or health failure returns nonzero even if an older executable still runs; describe completed effects and safe retry guidance.
- [ ] Preserve a positively identified permitted installation owner. An outdated installation owned by an unsupported or prohibited route fails with guidance instead of takeover or command shadowing. Do not silently downgrade custom builds or change prerelease channels.
- [ ] Do not create a second fnm shell integration. Combined shell selection uses the existing guarded native environment activation, and a failed environment command is never evaluated. Do not add automatic directory-change switching.
- [ ] Standalone fnm selection does not inspect or edit unselected shell configuration; report the command location and any native PATH/activation setup required by the Owner. Reusing Homebrew support must not become an implicit shell dependency.
- [ ] Install/update the manager only: preserve Node installations, default Node version, project version declarations, the native fnm data location, and unrelated runtime state. Do not set a relocation environment variable or install a default Node release.
- [ ] Preview forecasts routes and updates without latest-target network queries. Cancellation and dry-run produce no selected fnm updates or shell edits; selected configuration validation and the preparation-before-configuration gate remain in force for combinations.
- [ ] Cover macOS existing/missing Homebrew, current/outdated formulae, native credential refusal, Linux script success/failure, failed target lookup, unsupported owners, candidate/publication failures, current convergence, and a new target on the next invocation through the public entrypoints.
- [ ] Use real Zsh with controlled fnm executables in disposable homes to prove successful combined activation, rejection of failed environment output, continued later Owner code, and no duplicate initialization. Verify Node/state sentinels and standalone shell isolation remain unchanged.
- [ ] Document standalone and combined selection, the macOS Homebrew exception, Linux official-script trust limits, latest-target semantics, runtime exclusions, and recovery. Run focused route/runtime tests and existing integration regressions without real package-manager operations, downloads, or Node changes.
