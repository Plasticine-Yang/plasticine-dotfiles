# Publish v0.4.1

Status: done

Publish the patch through the existing Release workflow after the exact main
commit passes all four required CI jobs. User authorized publication.

## Comments

Published [v0.4.1](https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/tag/v0.4.1)
as the latest stable Release at `a1b2d517bb8a83b4b0a3e19a7da725728bb307b5`.
[CI run 37217943449](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/37217943449)
passed all four jobs. [Release run 37218303561](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/37218303561)
passed the exact-commit gate, asset build and digest verification. Verified the
public tag, five assets and recovery notes. A disposable live installation
upgraded from v0.4.0 to the published v0.4.1 package, then that package's own
self-update reported the same-version no-op successfully.
