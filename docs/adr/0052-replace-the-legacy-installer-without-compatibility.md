# Replace the legacy installer without compatibility code

The repository will cut over completely to the Go CLI and minimal Bootstrap: legacy component installers, uninstallers, checkout assumptions, flags, and obsolete instructions will be removed rather than migrated or detected at runtime. Existing `~/.plasticine-dotfiles` checkouts are a one-time manual cleanup after successful new Apply, avoiding both permanent compatibility debt and an unsafe historical `rm -rf` special case in the CLI.
