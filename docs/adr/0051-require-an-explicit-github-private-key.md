# Require an explicit GitHub private key reference

The GitHub SSH Component will accept a private-key path only from an interactive prompt or `--github-key` when first enabled or when no valid persisted Secret Reference exists; a later non-interactive Apply reuses a valid reference without another argument. The CLI will not scan standard SSH filenames, copy the key, or repair its permissions: it validates current-user ownership, regular-file shape, restrictive mode, readability by `ssh-keygen`, and the public fingerprint, leaving passphrase handling to Keychain or the shared agent.
