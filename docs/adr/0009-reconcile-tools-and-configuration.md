# Reconcile Managed Tools and their configuration

Reconciliation will own the installed version of each Managed Tool as well as its configuration. A Release will declare the desired tool versions and integrity metadata so a fresh Workstation can be provisioned without manual setup and repeated runs can detect missing, older, or newer tools instead of treating whatever happens to be installed as an acceptable prerequisite.
