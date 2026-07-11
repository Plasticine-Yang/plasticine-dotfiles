# Keep Secrets outside reconciliation

Secrets will remain local inputs rather than content managed by the repository, a Release, or Reconciliation. The CLI may validate that a required Secret is available, but it will not distribute, synchronize, persist, back up, or print its value, preventing repeatable configuration from also becoming a secret-distribution system.
