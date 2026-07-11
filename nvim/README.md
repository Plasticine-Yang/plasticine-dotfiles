# Neovim Reference Configuration

This directory contains handwritten Neovim configuration for manual inspection.
The release CLI owns any managed Neovim Desired State and installs the pinned
Neovim Managed Tool from Tool Lock data.

Plugin trees, generated loaders, caches, and other Neovim runtime data remain
Tool-managed State. They are not Release inputs and are not drift-checked,
backed up, or versioned by Plasticine.
