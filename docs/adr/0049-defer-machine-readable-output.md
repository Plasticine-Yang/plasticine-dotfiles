# Defer machine-readable output

The initial CLI will provide concise human-readable output, TTY-only color honoring `NO_COLOR`, and stable exit codes: zero for successful Plan or fully successful Apply and Doctor, one for operational blockers or unhealthy/partial outcomes, two for usage errors, and 130 for interruption. Internal outcomes remain structured, but no JSON schema becomes a compatibility commitment until a real consumer requires it.
