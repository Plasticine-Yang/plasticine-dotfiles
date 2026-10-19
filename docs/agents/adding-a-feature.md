# Adding a tool Feature

Use this checklist when a new independently selectable tool joins the installer. A Feature owns one tool's installation and maintenance route, plus any configuration it explicitly manages. Another Feature never turns it on implicitly.

## Touchpoints

| Area | File | What changes |
| --- | --- | --- |
| Selection | `install.sh` | usage text, `--<tool>` flag, `-y` guard, `PLASTICINE_TOOLS` assembly, selected detection, preview call |
| Menu | `.chezmoi.toml.tmpl` | add the tool to `$allowedTools` |
| Preparation | `.chezmoiscripts/run_before_04_prepare_selected_tools.sh.tmpl` | outer `or` condition and the plan/prepare block |
| Tool logic | `lib/<tool>-bootstrap.sh` (new) | `plan`, `preview`, `prepare`, error/log helpers, ownership and failure rules |
| Task record | `.scratch/<feature>/` | `spec.md` plus numbered implementation and release tickets |
| Feature suite | `tests/<tool>.sh` (new) | controlled fixtures for install, maintenance, ownership, failures, retry, and dry-run |
| Runtime suite | `tests/<tool>-runtime.sh` (new) | real Zsh checks for PATH and startup side effects |
| Check runner | `scripts/check.sh` | `all_suites`, per-suite required tools |
| CI | `.github/workflows/ci.yml` | timeout-runner steps for both suites |
| Workflow contract | `tests/workflows.sh` | assert CI runs the new suites |
| Combined install | `tests/combined-installation.sh` | fixture loop, targets, full-selection flags, expected `tools` list, prepare order, failure/retry |
| Static checks | `tests/integration.sh` | `sh -n` and ShellCheck lists |
| CLI pass-through | `tests/cli.sh` | add the flag to the byte-for-byte argument case |
| Documentation | `README.md` | intro, supported list, combinable flags, Feature section, local verification, Feature count, combined description |
| Release | new Base Release | the published installer and source bundle include the Feature only after a Release |

## Order

1. Write the spec and implementation ticket first; settle ownership and failure behavior before code.
2. Implement `lib/<tool>-bootstrap.sh`: `plan` only observes the machine, `prepare` performs every mutation.
3. Wire selection, menu, and the prepare script; keep the preview before confirmation.
4. Add both suites, then wire the check runner, CI, and the shared test lists.
5. Update README, run the relevant `scripts/check.sh` suites, and commit the implementation with its ticket.
6. Publish a Base Release before claiming the one-line installer supports the Feature.

## Invariants

- A standalone selection never edits shell startup files or selects `shell` implicitly.
- Preview, dry-run, cancel, and an unselected Feature perform no network access or native mutation.
- Healthy same-or-newer installations are reused. Unsupported owners, unhealthy targets, and unverifiable versions stop with guidance instead of being shadowed.
- Configuration is written only after every selected tool preparation succeeds.
- Tests canonicalize paths the same way production does; local checks receive `TMPDIR` through a symlink so macOS CI path shape is covered.
