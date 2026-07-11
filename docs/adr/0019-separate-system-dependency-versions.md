# Separate System Dependency version contracts

Release-pinned Managed Tools may be upgraded or downgraded to an exact version, while native packages such as Git, Zsh, and certificate bundles will be System Dependencies constrained only by presence, minimum version, or required capability. Reconciliation will install or upgrade an unsatisfied System Dependency through the platform package manager but will neither pin nor downgrade operating-system packages that the CLI does not fully own.
