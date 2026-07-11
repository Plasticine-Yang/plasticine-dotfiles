# Use launchers for relocated Tool-managed State

Stable `nvim`, `fnm`, `uv`, and `uvx` entries will be small atomically managed POSIX launchers that set only the supported directory environment needed to keep Tool-managed State under Plasticine Home before execing the exact versioned payload. Tools without such needs, including Lazygit and its `lg` alias, use symlinks; launchers contain no Reconciliation policy and ensure scripts or non-Zsh callers cannot bypass relocation.
