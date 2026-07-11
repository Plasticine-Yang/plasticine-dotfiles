# Pin GitHub SSH host keys in each Release

Each Release will embed GitHub's officially published SSH host keys and materialize a dedicated managed known-hosts file referenced alongside the Owner's existing file. The CLI will neither run `ssh-keyscan` nor trust the first connection; host-key rotation requires a new Release, while an older Release fails closed and Doctor diagnoses the mismatch without mutating GitHub.
