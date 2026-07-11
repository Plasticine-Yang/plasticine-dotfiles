# Verify Release artifacts with SHA-256

Bootstrap will verify the selected CLI binary against `checksums.txt` published with its Release, while Apply verifies each Managed Tool against the SHA-256 embedded in that Release's Tool Lock. The first version will not require GPG, minisign, cosign, or another verifier that may be absent on a fresh Workstation; this detects corruption and artifact mismatch while deliberately continuing to trust the GitHub account and Release publication path.
