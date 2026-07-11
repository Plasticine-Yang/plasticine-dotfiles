# Install Managed Tools in versioned user directories

Managed Tool payloads will be verified and atomically installed under `~/.plasticine/tools/<tool>/<version>`, with CLI-owned stable launch entries in `~/.plasticine/bin`. An entry is a symlink when no environment setup is needed and a minimal launcher otherwise; both are distinct from prohibited configuration-to-checkout links. After a successful switch, older tool payloads may be removed because Tool Lock can retrieve them again, and no tool installation writes `/usr/local/bin` or requires sudo.
