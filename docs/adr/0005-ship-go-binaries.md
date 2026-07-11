# Ship the Workstation CLI as Go binaries

The Workstation CLI will be developed in Go and shipped as a directly executable binary for macOS and Linux on both ARM64 and x86-64. A Workstation therefore needs no Go toolchain or language runtime: Bootstrap selects the matching Release artifact and executes it, trading a four-target build matrix for a small and dependable fresh-machine entrypoint. Other operating systems, architectures, and 32-bit machines are outside the initial contract.
