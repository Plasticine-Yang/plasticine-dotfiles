---
status: superseded by ADR-0054
---

# Store cross-platform state under XDG-style paths

Both macOS and Linux will install `plasticine` under `~/.local/bin`, keep versioned Reconciliation State and backups under `${XDG_STATE_HOME:-~/.local/state}/plasticine`, and use `${XDG_CACHE_HOME:-~/.cache}/plasticine` for replaceable downloads. There will be no user-editable configuration file because Desired State ships with the Release; if Reconciliation State is lost, existing paths become Conflicts rather than being guessed back into ownership.
