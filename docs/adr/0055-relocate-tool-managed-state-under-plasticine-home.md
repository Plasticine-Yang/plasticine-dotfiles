# Relocate Tool-managed State under Plasticine Home

Managed launchers and shell configuration will direct Neovim XDG state, Antidote home and Zsh runtime files, fnm's Node root, uv's cache/Python/tool roots, and the Linux SSH agent socket into `~/.plasticine/runtime`. Plasticine controls only those locations: their contents remain Tool-managed State outside Plan, drift, backup, and Release guarantees, while project-local environments and unavoidable operating-system runtime files retain native locations.
