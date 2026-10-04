# Credential-free self-update discovery

Fix the reported `curl: (22) ... 403` / `latest stable Release discovery failed`
failure caused by shared-IP anonymous GitHub REST API rate limits.

Discover the latest stable Plasticine Release from the public repository's
`/releases/latest` redirect without querying the REST API or requiring a token.
Only accept an HTTPS tag URL for this exact repository containing a stable
`vMAJOR.MINOR.PATCH` version. Reject absent, malformed, multiline, prerelease,
wrong-repository and wrong-origin redirects before downloading any assets.

Keep SHA-256, candidate validation, atomic switching, same-version no-op and
old-package preservation. The update must succeed in an integration fixture
where every REST discovery request fails with the user's exact HTTP 403 symptom.
Document one-time bootstrap recovery for immutable installed old updaters.
Verify, commit and publish patch Release v0.4.1 through the existing CI gate.
