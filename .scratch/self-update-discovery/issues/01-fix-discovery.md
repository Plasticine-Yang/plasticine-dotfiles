# Fix self-update anonymous API quota failures

Status: done

Implement and verify [the specification](../spec.md). User authorized the fix.

## Comments

The integration loop first failed with the exact HTTP 403 / discovery error.
After switching to the same-repository stable tag redirect it passes with the
API still blocked. Invalid redirects fail before downloads and preserve the
installed package. Verified POSIX sh and Bash, CLI delegation, ShellCheck and
the release pipeline. A disposable installation also completed a real anonymous
upgrade to v0.4.0 with SHA-256 and candidate validation. No debug instrumentation
was added. README documents recovery for already-installed old updaters.
