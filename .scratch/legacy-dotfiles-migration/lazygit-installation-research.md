# Lazygit Installation Research

Date: 2026-09-13
Scope: current official Lazygit installation paths from primary sources owned by `jesseduffield/lazygit` only

## Conclusion

Current official Lazygit does **not** appear to provide a maintained first-party "one-command/one-click installer script" for macOS/Linux in the repository or release assets. The official sources currently expose:

- package-manager install commands in the README
- a manual Debian/Ubuntu shell snippet that downloads a tarball and installs the binary
- release assets plus a `checksums.txt` file
- in-app self-update code for existing official binary installs

For our planned install flow, a **direct verified release download** remains the safer and simpler approach than invoking any official script, because there is no standalone official installer script to invoke, and the README shell snippet does **not** include checksum or signature verification.

## Primary-source findings

### 1. Official README does not present a first-party curl-pipe installer

The current README installation section offers package-manager routes and a manual shell snippet, not a dedicated Lazygit installer script:

- Binary releases are linked directly: <https://github.com/jesseduffield/lazygit/blob/master/README.md#binary-releases>
- Homebrew: <https://github.com/jesseduffield/lazygit/blob/master/README.md#homebrew>
- MacPorts: <https://github.com/jesseduffield/lazygit/blob/master/README.md#macports>
- Void: <https://github.com/jesseduffield/lazygit/blob/master/README.md#void-linux>
- `gah` for Linux and macOS is third-party, not Lazygit-owned: <https://github.com/jesseduffield/lazygit/blob/master/README.md#gah-linux-and-mac-os>
- Debian/Ubuntu manual snippet: <https://github.com/jesseduffield/lazygit/blob/master/README.md#debian-and-ubuntu>

Repository tree inspection at commit `d0ede21e9c1e13de255b78f28102450d4523d748` found no first-party installer entrypoint such as `install.sh`, `get.sh`, `installer`, or bootstrap script in the repo tree:

- Repository tree: <https://github.com/jesseduffield/lazygit/tree/master>
- Scripts directory: <https://github.com/jesseduffield/lazygit/tree/master/scripts>

### 2. macOS and Linux support in official sources

The README says binary releases are available for "Windows, Mac OS(10.12+) or Linux":

- <https://github.com/jesseduffield/lazygit/blob/master/README.md#binary-releases>

The current release workflow and Goreleaser config build archives for `darwin` and `linux`:

- Release workflow invokes Goreleaser: <https://github.com/jesseduffield/lazygit/blob/master/.github/workflows/release.yml>
- Goreleaser targets `darwin`, `linux`, `windows`, `freebsd`: <https://github.com/jesseduffield/lazygit/blob/master/.goreleaser.yml>

Current latest release assets include:

- macOS: `lazygit_0.65.0_darwin_arm64.tar.gz`, `lazygit_0.65.0_darwin_x86_64.tar.gz`
- Linux: `lazygit_0.65.0_linux_32-bit.tar.gz`, `lazygit_0.65.0_linux_arm64.tar.gz`, `lazygit_0.65.0_linux_armv6.tar.gz`, `lazygit_0.65.0_linux_x86_64.tar.gz`

Source:

- Latest release page: <https://github.com/jesseduffield/lazygit/releases/tag/v0.65.0>
- Latest release API endpoint owned by the repo: <https://api.github.com/repos/jesseduffield/lazygit/releases/latest>

### 3. Install destination and privilege requirements

The official Debian/Ubuntu manual snippet installs the extracted binary to `/usr/local/bin/` using `sudo install lazygit -D -t /usr/local/bin/`:

- README Debian/Ubuntu section: <https://github.com/jesseduffield/lazygit/blob/master/README.md#debian-and-ubuntu>

That means the documented official manual route:

- installs to `/usr/local/bin`
- requires elevated privileges for that destination because it uses `sudo`

I did not find a first-party macOS manual snippet in the Lazygit README that specifies a direct install destination outside package managers. For macOS, the official README points to package managers or downloading a binary release:

- README install section: <https://github.com/jesseduffield/lazygit/blob/master/README.md#installation>

### 4. Architecture handling

The only README shell snippet with architecture logic is the Debian/Ubuntu manual path:

```sh
LAZYGIT_ARCH=$(uname -m | sed -e 's/aarch64/arm64/')
```

Source:

- <https://github.com/jesseduffield/lazygit/blob/master/README.md#debian-and-ubuntu>

That snippet only normalizes `aarch64` to `arm64`; it does not show a broader architecture mapping table.

The actual release build matrix and archive naming are defined in `.goreleaser.yml`:

- `amd64 -> x86_64`
- `386 -> 32-bit`
- `arm -> armv6`
- `arm64 -> arm64`

Source:

- <https://github.com/jesseduffield/lazygit/blob/master/.goreleaser.yml>

The in-app updater code has similar mapping logic for official binary releases:

- `darwin -> Darwin`, `linux -> Linux`, `windows -> Windows`
- `amd64 -> x86_64`, `386 -> 32-bit`
- archive extension is `.tar.gz` on non-Windows and `.zip` on Windows

Source:

- <https://github.com/jesseduffield/lazygit/blob/master/pkg/updates/updates.go>

Important nuance: current release assets are published with lower-case OS names such as `linux` and `darwin` per `.goreleaser.yml` and the latest release asset list, while the README Debian/Ubuntu snippet still uses `Linux` in the filename template. This suggests the README snippet is at least stylistically stale and should not be treated as a stronger source than the release asset list itself.

Sources:

- <https://github.com/jesseduffield/lazygit/blob/master/.goreleaser.yml>
- <https://github.com/jesseduffield/lazygit/releases/tag/v0.65.0>
- <https://github.com/jesseduffield/lazygit/blob/master/README.md#debian-and-ubuntu>

### 5. Latest-version resolution

The README Debian/Ubuntu snippet resolves the latest version by querying the GitHub releases API and extracting `tag_name`:

```sh
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | \grep -Po '"tag_name": *"v\K[^"]*')
```

Source:

- <https://github.com/jesseduffield/lazygit/blob/master/README.md#debian-and-ubuntu>

The application updater resolves the latest version in the same repo-owned direction by requesting `https://github.com/jesseduffield/lazygit/releases/latest` with `Accept: application/json` and decoding `tag_name`.

Source:

- <https://github.com/jesseduffield/lazygit/blob/master/pkg/updates/updates.go>

### 6. Checksum and signature verification

The release process explicitly emits a `checksums.txt` asset:

- Goreleaser config: <https://github.com/jesseduffield/lazygit/blob/master/.goreleaser.yml>
- Latest release assets: <https://github.com/jesseduffield/lazygit/releases/tag/v0.65.0>
- Current checksum file asset: <https://github.com/jesseduffield/lazygit/releases/download/v0.65.0/checksums.txt>

However, in the official sources I reviewed, I found:

- **checksum file present**
- **no documented checksum verification step in the README manual snippet**
- **no signature, minisign, cosign, GPG, or notarization artifact exposed in the current release assets**
- **no first-party installer script that performs verification on the user's behalf**

So the official source-of-truth supports checksum verification as a manual step via `checksums.txt`, but it does not currently package a signed installer or document a complete verified install command in the README.

### 7. Whether any official script is safer/simpler than direct verified release download

Based on the current official sources, the answer is **no**.

Reasons:

- There is no standalone official install script in the repository tree or release assets to prefer over a direct binary download.
- The README manual snippet is only a convenience shell sequence, not a maintained installer artifact.
- That snippet does not verify the downloaded tarball against `checksums.txt`.
- The repo does publish `checksums.txt`, so a direct release download plus explicit checksum verification gives a clearer trust chain than copying the README snippet as-is.
- The in-app updater is not a bootstrap installer. It is code inside Lazygit for updating an already installed official binary and does not help with initial installation.

Relevant sources:

- README install section: <https://github.com/jesseduffield/lazygit/blob/master/README.md#installation>
- Scripts directory: <https://github.com/jesseduffield/lazygit/tree/master/scripts>
- Release workflow: <https://github.com/jesseduffield/lazygit/blob/master/.github/workflows/release.yml>
- Goreleaser config: <https://github.com/jesseduffield/lazygit/blob/master/.goreleaser.yml>
- Updater code: <https://github.com/jesseduffield/lazygit/blob/master/pkg/updates/updates.go>

## Practical recommendation for our migration

Prefer a repo-controlled install flow that:

1. resolves a specific Lazygit version intentionally
2. downloads the exact official release asset for the target OS/arch
3. verifies it against official `checksums.txt`
4. installs to our chosen destination explicitly

That is both more auditable and more robust than relying on the current README shell snippet, and there is no official Lazygit installer script offering a better alternative today.
