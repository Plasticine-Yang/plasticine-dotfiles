# Limit full Linux support to Debian and Ubuntu

The Linux CLI binary and user-scoped Reconciliation will support ARM64 and x86-64 broadly, while full Reconciliation involving native packages or services will initially target Debian and Ubuntu releases at or above their declared Support Floors through `apt` and systemd. Older releases and other Linux distributions will report unsupported System Changes instead of guessing commands, keeping the first Release honest and small while leaving compatible user-scoped configuration portable on a best-effort basis.
