# Release the CLI and configuration together

Each Release will freeze the Workstation CLI and its non-secret configuration assets as one immutable versioned unit. Reconciliation will use only that snapshot instead of reading a mutable `main` branch or a workstation checkout, so selecting the same version later produces the same intended state; a repository checkout remains a development concern rather than an installation dependency.
