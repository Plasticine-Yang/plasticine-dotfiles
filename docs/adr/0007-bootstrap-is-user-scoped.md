# Keep Bootstrap user-scoped

Bootstrap will run without privilege escalation and install the Workstation CLI atomically under `~/.plasticine/bin`. It will invoke the installed binary by absolute path, leaving PATH reconciliation to the CLI; this avoids making the network-piped entrypoint a privileged system installer while still supporting a fresh shell environment.
