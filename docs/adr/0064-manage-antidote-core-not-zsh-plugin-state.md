# Manage Antidote core but not Zsh plugin state

Antidote will be treated as shell infrastructure managed by the `shell` Component: the Release pins and verifies the Antidote source payload through Tool Lock, then exposes it through managed Zsh configuration. Antidote's cloned plugin repositories, generated static bundle, snapshots, compinit dumps, compiled files, and update logs remain Tool-managed State under Plasticine Home, because Plasticine should make the plugin manager available without pretending to own or checksum its transitive plugin ecosystem.
