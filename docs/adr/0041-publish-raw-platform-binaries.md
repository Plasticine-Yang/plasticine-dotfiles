# Publish raw platform binaries

Each Release will publish one directly executable `plasticine` binary for each of the four Artifact Targets, `checksums.txt`, and the small `install.sh` Bootstrap, without a tar or gzip wrapper. Bootstrap therefore needs only target mapping, HTTPS download, SHA-256 verification, chmod, and handoff logic, deliberately spending additional bandwidth to keep the network-executed shell entrypoint smaller and easier to audit.
