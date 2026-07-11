# Build Releases reproducibly

Release CI will pin the Go toolchain and module graph, build all targets with `CGO_ENABLED=0`, read-only modules, and trimmed paths, and embed only tag, commit SHA, and source-derived commit time. It will reject tag/version or lock inconsistencies and avoid UPX or machine-specific metadata, making a tagged artifact independently rebuildable without expanding the build chain.
