# Serve Bootstrap from the latest stable Release

The fixed curl URL will resolve `install.sh` from GitHub's latest stable Release rather than the mutable `main` branch. Each published Bootstrap is therefore immutable with its Release while still supporting an explicit `PLASTICINE_VERSION` for candidate selection; unpublished repository changes cannot enter the remote execution path.
