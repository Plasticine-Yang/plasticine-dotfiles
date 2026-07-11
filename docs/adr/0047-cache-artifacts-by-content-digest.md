# Cache artifacts by content digest

Apply will cache downloads under `~/.plasticine/cache/artifacts/<sha256>`, reverify every hit, and atomically promote verified partial downloads. Plan never uses the network, failures remain local to dependent Components, and the standard Go HTTP transport honors conventional proxy environment variables without logging proxy values that may contain credentials; the first CLI exposes no offline or cache-management mode.
