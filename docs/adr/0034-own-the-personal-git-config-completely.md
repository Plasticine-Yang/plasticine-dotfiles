# Own the personal Git configuration completely

When `git-config` is active, Reconciliation will own the complete personal Git configuration under `~/.plasticine/config/git/config` and a minimal `~/.gitconfig` shim that includes it, without local override fragments or the plaintext credential store. If `github-ssh` is also active its URL rewrite is composed into that same Desired State; excluding `git-config` leaves a company-controlled Git configuration entirely unread, unbacked-up, and unmodified.
