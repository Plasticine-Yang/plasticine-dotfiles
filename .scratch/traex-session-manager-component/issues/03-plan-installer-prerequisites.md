# 03 — Plan installer prerequisites across supported Workstations

**What to build:** Ensure the Owner learns about every local prerequisite before an external TSM installer begins, using Plasticine's existing System Dependency and authorization behavior consistently across the complete Workstation support matrix.

**Blocked by:** 01 — Bootstrap a missing TSM installation.

**Status:** ready-for-agent

- [ ] Plan checks for `curl`, `tar`, and a usable SHA-256 verifier whenever the active TSM Component requires bootstrap or repair.
- [ ] Either `shasum` or `sha256sum` satisfies the SHA-256 verification capability.
- [ ] Plan remains read-only and performs no installer or release network request while checking prerequisites.
- [ ] When TSM is already runnable or excluded, its installer-only prerequisites do not create unnecessary System Dependency changes or blockers.
- [ ] Supported Debian and Ubuntu hosts map missing prerequisites to appropriate native packages through the existing System Dependency mechanism.
- [ ] Missing Linux packages require the existing `--allow-system` authorization in addition to ordinary Apply authorization; `--yes` alone does not grant it.
- [ ] Supported macOS hosts report existing Owner-action behavior when an installer prerequisite cannot be satisfied automatically.
- [ ] Prerequisite application failure blocks TSM but continues unrelated Components according to the existing dependency graph rules.
- [ ] macOS amd64, macOS arm64, Linux amd64, and Linux arm64 all expose the same default Component and correct platform-specific prerequisite outcomes.
- [ ] Contract tests cover satisfied, missing, alternatively satisfied, authorization-denied, application-failed, excluded, and already-runnable prerequisite scenarios without relying on host-machine tools.
