# 01 — Bootstrap a missing TSM installation

**What to build:** Add the first complete Self-managed Tool path so the Owner can see `traex-session-manager` in Plasticine, review an opaque upstream-installer change, authorize Apply normally, receive a runnable `tsm`, and verify its health through Doctor without bringing TSM under version management.

**Blocked by:** None — can start immediately.

**Status:** ready-for-human

- [x] `traex-session-manager` is a default-enabled Component and appears consistently in Component selection, Plan, Apply, Doctor, CLI output, and the TUI.
- [x] Self-managed Tool is represented by a reusable Release-owned descriptor whose interface is limited to Component identity, HTTPS installer URL, primary executable, health command, prerequisite capabilities, and timeout.
- [x] When the fixed primary executable is absent, Plan reports one explicit opaque external-installer change containing the reviewed installer URL and external-script risk without performing a network request.
- [x] When the fixed primary executable already passes its health command, Plan reports no TSM change regardless of its version text.
- [x] Ordinary interactive authorization or `--yes` permits the external installer; denial occurs before any download or script execution and no new authorization flag is introduced.
- [x] Apply can download a deterministic fixture installer, execute it, rerun the primary health command, and report the Component succeeded only when that command passes.
- [x] A successful bootstrap leaves TSM outside Tool Lock and does not promise or render an installed version.
- [x] Doctor checks the active Component through the fixed primary health command without checking for updates or making a network request.
- [x] Reconciler contract tests exercise Plan, Apply, and Doctor through isolated Workstation state and local test adapters rather than real GitHub or a real remote script.
- [x] Thin CLI and TUI tests verify the Component name, opaque installer risk, ordinary authorization, and healthy result are visible without duplicating Reconciler behavior tests.

## Comments

- Implemented through the Reconciler Plan/Apply/Doctor seam with deterministic HTTP and command adapters.
- Verified by `TestTSMBootstrapPlanApplyAndDoctorContract`, `TestTSMComponentIsDefaultEnabledOnEveryArtifactTarget`, and thin CLI/TUI rendering tests.
