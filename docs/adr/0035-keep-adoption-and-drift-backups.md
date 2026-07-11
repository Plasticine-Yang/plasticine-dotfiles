# Keep adoption and drift backups indefinitely

Reconciliation will create an immutable unique backup before adopting an unmanaged path and before overwriting Owner-created drift, but not for an ordinary Release update whose current content still matches the previous Desired State. Backups remain ordinary files under a `0700` state directory with no automatic pruning or initial restore command; explicit Secret Reference targets are never copied, while any opaque content inside an adopted configuration snapshot is retained locally without inspection or logging.
