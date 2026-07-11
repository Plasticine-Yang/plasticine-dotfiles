# Fix the initial Component graph

The stable initial Component IDs are `shell`, `git-config`, `github-ssh`, `neovim`, `lazygit`, `fnm`, and `uv`. `github-ssh` and `fnm` require `shell`; enabled Components derive non-excludable Zsh, Git, OpenSSH, and CA System Dependencies as needed, and the shell owns PATH integration. GitHub URL rewriting is composed only when both personal Git and SSH Components are active, so company Scope can exclude both without suppressing Git software needed elsewhere.
