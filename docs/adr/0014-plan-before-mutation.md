# Complete a Plan before mutation

Reconciliation will finish read-only discovery and produce a complete Plan before any mutation begins. The `plan` command displays it and Apply executes the same representation after one interactive confirmation or `--yes`; a Plan containing System Changes additionally requires `--allow-system`, and any planning failure exits with zero changes so discovery and mutation remain independently testable.
