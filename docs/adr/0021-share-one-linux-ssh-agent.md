# Share one SSH agent across Linux terminals

On Debian and Ubuntu, the GitHub SSH Component will run one user-level systemd `ssh-agent` on a fixed socket, export that socket to every managed shell, and call `ssh-add` only when the configured key fingerprint is absent. Terminal sessions therefore share authentication without repeated `eval` setup; an encrypted key may prompt once after the agent restarts, while persisting its passphrase through a desktop keyring remains outside the first Release. macOS will use its native Keychain integration instead.
