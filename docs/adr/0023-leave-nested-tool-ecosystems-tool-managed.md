# Leave nested tool ecosystems tool-managed

Reconciliation will materialize the Owner's configuration and exact Managed Tool binaries but will not own the ecosystems those tools manage. Zsh and Neovim may bootstrap plugin managers and resolve plugins natively; fnm owns Node versions and aliases; uv owns Python versions, environments, and installed tools. These nested states and failures remain tool-local rather than Apply concerns, deliberately limiting Release reproducibility to managed configuration and binaries rather than their transitive ecosystems.
