# Materialize managed configuration

Reconciliation will atomically materialize configuration content at each Managed Path rather than linking it to a repository checkout or extracted Release. Installed configuration therefore survives checkout moves and Release cleanup, while local edits become observable drift against the immutable desired content instead of mutations to the Release itself.
