# Batch missing apt dependencies

On Debian and Ubuntu, Plan will aggregate all missing System Dependency packages and one authorized Apply will run `sudo apt-get update` followed by one `sudo apt-get install -y --no-install-recommends` invocation. It will not perform a global upgrade, downgrade satisfied packages, or transport sudo credentials; passwordless environments may run non-interactively, while a missing TTY for required authentication fails explicitly.
