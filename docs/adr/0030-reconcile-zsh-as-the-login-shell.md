# Reconcile Zsh as the login shell

The `shell` Component will ensure the Zsh System Dependency is present and the Owner's account selects the resolved Zsh binary as its login shell. A required `chsh` operation is an explicit System Change with normal authorization and credential prompts; Apply will not source configuration or replace its own process, and the new shell takes effect only in a later terminal or login session.
