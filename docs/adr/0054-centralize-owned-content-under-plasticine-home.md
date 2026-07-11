# Centralize owned content under Plasticine Home

All persistent content associated with plasticine will live under the `0700` `~/.plasticine` root: binaries, versioned tool payloads, managed configuration bodies, state, journals, locks, backups, artifact cache, and a `runtime` subtree for relocated Tool-managed State. Only unavoidable materialized shims remain at conventional paths such as `~/.zshrc`, `~/.gitconfig`, and the marked SSH include; launchers and supported environment variables point tools at centralized paths without making runtime content part of Reconciliation.
