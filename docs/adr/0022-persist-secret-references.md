# Persist Secret References, not Secrets

The Workstation CLI may retain a normalized private-key path and its public fingerprint as a Secret Reference so later Plan and Apply runs need no repeated argument. It will not copy, back up, or record the private key or passphrase; a missing file, unsafe permission, or changed fingerprint becomes a blocker until the Owner explicitly selects the key again.
