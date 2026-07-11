# plasticine-dotfiles

Owner-specific Workstation bootstrap and reconciliation assets.

## Install

The canonical install entry is the minimal Bootstrap script published with a
GitHub Release. It selects a raw `plasticine` binary for the current Artifact
Target, verifies `checksums.txt`, marks the candidate executable, and hands off
to the candidate CLI.

```sh
curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh | sh
```

Select an exact immutable version with `PLASTICINE_VERSION`:

```sh
curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh | PLASTICINE_VERSION=v0.1.0 sh
```

Prereleases are never selected by the default latest-stable path; choose them
explicitly with `PLASTICINE_VERSION`.
When GitHub offers immutable Release assets for the repository, keep that
setting enabled; the publication workflow also refuses duplicate tags or assets.

## CLI

The public command surface is intentionally small:

```sh
plasticine version
plasticine plan
plasticine apply --yes
plasticine doctor
```

`plan` is read-only. `apply` executes the internally generated plan and requires
`--yes` for non-interactive authorization. Any planned System Change requires the
separate `--allow-system` authorization. `doctor` performs safe diagnostics and
does not mutate local state.

Component narrowing and Workstation Scope are part of the Reconciler contract.
Company Workstations can persistently exclude personal components such as
`git-config`; when personal Git configuration is excluded, Plasticine does not
read, back up, or modify company-controlled Git configuration.

GitHub SSH setup requires an explicit private-key path from the Owner. Public-key
registration on GitHub remains manual. macOS uses native Keychain behavior, and
supported Linux Workstations use one shared user-level SSH agent.

## Reference Configuration

VS Code material under `reference/vscode` is retained only for manual copying.
It is not a Release input, is never planned or applied, and does not enter
ownership or drift checks.

## Platform Boundary

Release artifacts are four raw executables plus `checksums.txt` and
`install.sh`:

- `plasticine_darwin_amd64`
- `plasticine_darwin_arm64`
- `plasticine_linux_amd64`
- `plasticine_linux_arm64`

Full Reconciliation support floors are macOS 13, Debian 12, and Ubuntu 22.04 on
amd64 and arm64. Other compatible 64-bit Linux systems may run binary and
user-scoped behavior, but unsupported System Changes are reported instead of
guessed.

After a successful new `apply`, any old repository checkout is a manual cleanup
concern. The CLI does not perform guessed deletion of historical directories.

## Development Gates

Run the full local release gate:

```sh
scripts/validate-release.sh
```

The gate runs Go tests, Bootstrap syntax/ShellCheck validation when available,
Tool Lock validation, four-target reproducible builds, checksum consistency, and
native smoke checks using an isolated temporary HOME.
