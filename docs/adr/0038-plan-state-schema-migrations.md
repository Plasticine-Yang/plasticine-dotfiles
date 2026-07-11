# Plan Reconciliation State schema migrations

Reconciliation State will carry a schema version, and a newer CLI may translate older versions only in memory during read-only discovery. Plan exposes the required migration and Apply atomically persists it after authorization; corrupted or unknown newer schemas block without writes, and older CLIs never attempt a downgrade, preserving the Plan/Apply and limited rollback contracts.
