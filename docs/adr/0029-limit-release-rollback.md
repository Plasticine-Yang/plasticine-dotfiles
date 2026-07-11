# Limit Release rollback to compatible managed state

Before replacing the installed CLI with an explicitly selected older Release, Bootstrap will run the candidate against existing Reconciliation State in read-only compatibility mode. A compatible candidate may reconcile older managed configuration and exact Managed Tool versions, while System Dependencies and Tool-managed State are never downgraded; an incompatible state schema aborts before replacement, so version selection does not pretend to be a whole-Workstation snapshot restore.
