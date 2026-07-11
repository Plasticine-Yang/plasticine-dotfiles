# Set operating-system support floors

The first stable Release sets Support Floors of macOS 13, Debian 12, and Ubuntu 22.04 for the full Reconciliation contract on both amd64 and arm64. Release CI uses a finite matrix covering those floors where runners are available plus selected current representatives; it does not model every newer point release as a separate Artifact Target or test gate. Older releases of those systems and other 64-bit Linux distributions may run a compatible binary and user-level actions on a best-effort basis, but they do not receive the full System Change contract.
