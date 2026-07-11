# Publish immutable SemVer Releases

Pushing a `vX.Y.Z` tag will run all gates, build the four platform artifacts, generate checksums, and assemble a draft GitHub Release that is published only when complete. Version, commit, and build metadata are embedded in the binary; published tags and assets are never replaced, prerelease tags require explicit selection, and Bootstrap's default latest path resolves only a stable published Release.
