# Update Managed Tools only through Tool Lock

Managed Tool versions change only through a reviewed repository edit to `tools.lock.json`, which records an immutable version URL, archive type, and SHA-256 for every Artifact Target. Helper tooling may prepare candidate hashes but cannot commit or publish automatically; CI validates the complete target matrix, Runtime never resolves `latest`, `stable`, or branches, and no scheduled updater changes the Owner's Workstations implicitly.
