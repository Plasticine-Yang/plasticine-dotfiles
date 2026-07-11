# Escalate privilege per System Change

The Workstation CLI will always start as the ordinary user and elevate only the concrete subprocess needed for an explicitly planned System Change. Interactive runs require confirmation and non-interactive runs require an explicit `--allow-system`; the complete CLI and user-scoped Reconciliation will never run as root, preserving least privilege without excluding system packages, `/etc` files, or services from the intended state.
