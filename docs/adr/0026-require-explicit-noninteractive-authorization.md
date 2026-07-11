# Require explicit non-interactive authorization

Bootstrap-invoked Apply will read its Plan confirmation from `/dev/tty` when available so the curl pipe does not consume the interaction channel. Without a TTY it may install the CLI but will refuse Reconciliation and return nonzero unless `--yes` is explicit; a Plan containing System Changes still requires `--allow-system`, and CI detection never grants either permission implicitly.
