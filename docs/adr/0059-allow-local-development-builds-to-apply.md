# Allow local development builds to Apply

A locally built or `go run` development CLI may Plan and Apply the current working tree's embedded Desired State so configuration changes need no throwaway tag. It reports dev commit and dirty metadata, records a Desired State digest rather than impersonating SemVer, and cannot enter the hidden self-install path; Bootstrap continues selecting only published Releases, which can later reconcile normally from a development-applied state.
