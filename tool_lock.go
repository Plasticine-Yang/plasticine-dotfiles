package plasticine

import _ "embed"

// DefaultToolLockJSON is embedded into release binaries so runtime behavior does
// not depend on a repository checkout or the current working directory.
//
//go:embed tool-lock.json
var DefaultToolLockJSON []byte
