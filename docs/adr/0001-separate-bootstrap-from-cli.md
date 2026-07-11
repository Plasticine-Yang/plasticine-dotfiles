# Separate Bootstrap from workstation configuration

The curl entrypoint will remain a minimal Bootstrap whose responsibility ends after it obtains and launches a selected release of the Workstation CLI. Configuration and reconciliation belong to the versioned CLI so they can be tested, evolved, and run repeatedly without growing an opaque shell installer; this deliberately trades a self-contained install script for a release-distribution boundary.
