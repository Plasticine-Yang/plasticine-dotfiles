# npmrc script preference

Add an independently selectable `npmrc` Feature and `--npmrc` installer flag.
The Feature manages only `dangerously-allow-all-scripts=true` in `~/.npmrc`.
Preserve every other Owner setting, especially `ignore-scripts`, registry and
authentication configuration. Do not install Node/npm or execute package scripts.

Use the existing empty-by-default selection and `-y` contract. Preview must show
the managed preference without printing credentials. Apply follows successful
selected-tool preparation, backs up a changed existing file privately, retains
its mode and converges without rewriting or creating another backup. Reject
unsafe target/backup paths before any selected configuration is written.

Verify with integration scripts and real npm using an offline local package:
the baseline blocks postinstall, the preference enables it, and an explicit
ignore-scripts setting retains npm precedence. Update README and publish v0.4.0
through the existing Release workflow after CI succeeds.
