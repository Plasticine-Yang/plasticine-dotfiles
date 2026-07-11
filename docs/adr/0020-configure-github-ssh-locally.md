# Configure GitHub SSH locally

The GitHub SSH Component will accept a reference to an Owner-provided private key and configure local OpenSSH and the SSH agent to use it for GitHub. When `git-config` is also active, their composed Desired State rewrites `https://github.com/` Git URLs to the SSH transport. The CLI will neither copy or back up the private key nor register the public key with GitHub; remote key registration remains manual, and the obsolete plaintext `credential.helper = store` setting will leave the personal Git Desired State.
