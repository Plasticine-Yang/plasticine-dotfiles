#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
case $chezmoi_bin in /*) ;; *) chezmoi_bin=$(command -v "$chezmoi_bin") ;; esac
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-uv-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'uv test: %s\n' "$1" >&2; exit 1; }
# Isolate the native receipt/install destinations from the caller's HOME.
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_BIN_HOME UV_INSTALL_DIR UV_NO_MODIFY_PATH \
    UV_UNMANAGED_INSTALL UV_DISABLE_UPDATE UV_PYTHON_INSTALL_DIR UV_TOOL_BIN_DIR
fixture_bin=$test_root/bin
mkdir -p "$fixture_bin"

cat > "$test_root/uv" <<'UV'
#!/bin/sh
set -eu
self=$0
printf '%s\n' "$*" >> "$PLASTICINE_TEST_UV_CALLS"
case ${1:-} in
    --version) printf '%s %s\n' "${self##*/}" "$(cat "$self.version")" ;;
    self)
        [ "${2:-}" = update ] || exit 90
        [ "${PLASTICINE_TEST_UV_FAIL:-}" != self-update ] || exit 91
        printf '%s\n' "${PLASTICINE_TEST_UV_LATEST:-$(cat "$self.version")}" > "$self.version"
        printf '%s\n' "${PLASTICINE_TEST_UV_LATEST:-$(cat "${self%/*}/uvx.version")}" > "${self%/*}/uvx.version"
        ;;
    *) exit 92 ;;
esac
UV

cat > "$test_root/env.stock" <<'HELPER'
#!/bin/sh
# add binaries to PATH if they aren't added yet
# affix colons on either side of $PATH to simplify matching
case ":${PATH}:" in
    *:"$HOME/.local/bin":*)
        ;;
    *)
        # Prepending path in case a system-installed binary needs to be overridden
        export PATH="$HOME/.local/bin:$PATH"
        ;;
esac
HELPER

# The shape a hand-edited helper takes: executable and delegating with exec.
cat > "$test_root/env.shim" <<'HELPER'
#!/bin/sh
# add binaries to PATH if they aren't added yet
# affix colons on either side of $PATH to simplify matching
case ":${PATH}:" in
    *:"$HOME/.local/bin":*)
        ;;
    *)
        # Prepending path in case a system-installed binary needs to be overridden
        export PATH="$HOME/.local/bin:$PATH"
        ;;
esac

# Delegate to the real env; this script only adjusts PATH, it is not a replacement.
exec /usr/bin/env "$@"
HELPER

cat > "$fixture_bin/curl" <<'CURL'
#!/bin/sh
set -eu
out=''
url=''
while [ "$#" -gt 0 ]; do
    case $1 in
        -o) out=$2; shift ;;
        -fsSL|-fsS|-fsL) ;;
        https://astral.sh/uv/install.sh) url=$1 ;;
        *) exit 96 ;;
    esac
    shift
done
[ -n "$out" ] && [ -n "$url" ] || exit 96
printf '%s\n' download >> "$PLASTICINE_TEST_UV_CALLS"
[ "${PLASTICINE_TEST_UV_FAIL:-}" != download ] || exit 22
cat > "$out" <<'INSTALLER'
#!/bin/sh
set -eu
APP_NAME="uv"
APP_VERSION="0.13.1"
printf '%s\n' installer >> "$PLASTICINE_TEST_UV_CALLS"
printf 'sha256sum=%s\n' "$(command -v sha256sum || true)" >> "$PLASTICINE_TEST_UV_CALLS"
[ "${UV_INSTALL_DIR:-}" = "$PLASTICINE_TEST_UV_BIN_DIR" ] || exit 97
[ "${UV_NO_MODIFY_PATH:-}" = 1 ] || exit 97
[ "${UV_UNMANAGED_INSTALL:-}" = '' ] || exit 97
[ "${UV_DISABLE_UPDATE:-}" = '' ] || exit 97
[ "${HOME:-}" = "$PLASTICINE_TEST_UV_HOME" ] || exit 97
[ "${PLASTICINE_TEST_UV_FAIL:-}" != installer ] || exit 98
mkdir -p "$UV_INSTALL_DIR"
cp "$PLASTICINE_TEST_UV_TEMPLATE" "$UV_INSTALL_DIR/uv"
cp "$PLASTICINE_TEST_UV_TEMPLATE" "$UV_INSTALL_DIR/uvx"
chmod 755 "$UV_INSTALL_DIR/uv" "$UV_INSTALL_DIR/uvx"
printf '%s\n' "$PLASTICINE_TEST_UV_VERSION" > "$UV_INSTALL_DIR/uv.version"
printf '%s\n' "$PLASTICINE_TEST_UV_VERSION" > "$UV_INSTALL_DIR/uvx.version"
receipt_dir=${XDG_CONFIG_HOME:-$HOME/.config}/uv
mkdir -p "$receipt_dir"
printf '{"install_prefix":"%s","modify_path":false}\n' "$UV_INSTALL_DIR" > "$receipt_dir/uv-receipt.json"
case ${PLASTICINE_TEST_UV_ENV_HELPER:-shim} in
    none) ;;
    stock)
        cp "$PLASTICINE_TEST_UV_ENV_STOCK" "$UV_INSTALL_DIR/env"
        chmod 644 "$UV_INSTALL_DIR/env"
        ;;
    *)
        cp "$PLASTICINE_TEST_UV_ENV_SHIM" "$UV_INSTALL_DIR/env"
        chmod 755 "$UV_INSTALL_DIR/env"
        ;;
esac
INSTALLER
CURL
chmod 755 "$fixture_bin/curl"

new_case() {
    printf 'uv scenario: %s\n' "$1" >&2
    scenario=$test_root/$1
    mkdir -p "$scenario/home" "$scenario/config"
    # The module canonicalizes its destination, so expectations must use the
    # physical path even when TMPDIR (for example on macOS runners) is a link.
    scenario_home=$(cd -- "$scenario/home" && pwd -P)
    printf '%s\n' '[data]' 'tools = ["uv"]' > "$scenario/config/chezmoi.toml"
    : > "$scenario/calls"
}
apply_case() {
    (
        PATH=$fixture_bin:/usr/bin:/bin
        HOME=$scenario_home
        PLASTICINE_CHEZMOI_DEST_DIR=$scenario_home
        PLASTICINE_TEST_UV_CALLS=$scenario/calls
        PLASTICINE_TEST_UV_TEMPLATE=$test_root/uv
        PLASTICINE_TEST_UV_VERSION=${PLASTICINE_TEST_UV_VERSION:-0.13.1}
        PLASTICINE_TEST_UV_LATEST=${PLASTICINE_TEST_UV_LATEST:-}
        PLASTICINE_TEST_UV_HOME=$scenario_home
        PLASTICINE_TEST_UV_BIN_DIR=$scenario_home/.local/bin
        PLASTICINE_TEST_UV_ENV_HELPER=${PLASTICINE_TEST_UV_ENV_HELPER:-shim}
        PLASTICINE_TEST_UV_ENV_SHIM=$test_root/env.shim
        PLASTICINE_TEST_UV_ENV_STOCK=$test_root/env.stock
        export PATH HOME PLASTICINE_CHEZMOI_DEST_DIR PLASTICINE_TEST_UV_CALLS \
            PLASTICINE_TEST_UV_TEMPLATE PLASTICINE_TEST_UV_VERSION \
            PLASTICINE_TEST_UV_LATEST PLASTICINE_TEST_UV_HOME PLASTICINE_TEST_UV_BIN_DIR \
            PLASTICINE_TEST_UV_ENV_HELPER PLASTICINE_TEST_UV_ENV_SHIM PLASTICINE_TEST_UV_ENV_STOCK
        exec "$chezmoi_bin" -S "$repo_dir" -D "$scenario_home" -c "$scenario/config/chezmoi.toml" \
            --persistent-state "$scenario/state" apply --no-tty "$@"
    )
}
expect_failure() {
    if apply_case > "$scenario/out" 2> "$scenario/err"; then fail "$1 was accepted"; fi
}
seed_managed() {
    mkdir -p "$scenario/home/.local/bin" "$scenario/home/.config/uv"
    cp "$test_root/uv" "$scenario/home/.local/bin/uv"
    cp "$test_root/uv" "$scenario/home/.local/bin/uvx"
    chmod 755 "$scenario/home/.local/bin/uv" "$scenario/home/.local/bin/uvx"
    printf '%s\n' "${1:-0.13.1}" > "$scenario/home/.local/bin/uv.version"
    printf '%s\n' "${1:-0.13.1}" > "$scenario/home/.local/bin/uvx.version"
    printf '{"install_prefix":"%s","modify_path":false}\n' \
        "$scenario_home/.local/bin" > "$scenario/home/.config/uv/uv-receipt.json"
}
assert_sha256_route() {
    # The upstream installer only verifies archives when sha256sum exists.
    # macOS must receive the shasum-backed shim; Linux uses the native tool.
    sha_route=$(grep -F 'sha256sum=' "$scenario/calls" | tail -n 1 || true)
    if [ -z "$sha_route" ]; then fail 'installer could not resolve sha256sum'; fi
    case $(uname -s) in
        Darwin)
            case $sha_route in
                *plasticine-uv.*/bin/sha256sum) ;;
                *) fail 'macOS archive verification did not use the shasum shim' ;;
            esac ;;
        Linux)
            case $sha_route in
                *plasticine-uv.*) fail 'Linux unnecessarily replaced native sha256sum' ;;
            esac ;;
    esac
}

new_case fresh
printf '%s\n' owner > "$scenario/home/.zshrc"
mkdir -p "$scenario/home/project"
printf '%s\n' 3.12 > "$scenario/home/project/.python-version"
cp "$scenario/home/project/.python-version" "$scenario/project-before"
apply_case > "$scenario/out"
grep -Fxq download "$scenario/calls" || fail 'missing uv did not use the official installer'
grep -Fxq installer "$scenario/calls" || fail 'official installer was not executed'
[ -x "$scenario/home/.local/bin/uv" ] && [ -x "$scenario/home/.local/bin/uvx" ] ||
    fail 'uv/uvx were not installed'
[ "$(cat "$scenario/home/.local/bin/uv.version")" = 0.13.1 ] || fail 'installed uv version is wrong'
grep -Fq "\"install_prefix\":\"$scenario_home/.local/bin\"" \
    "$scenario/home/.config/uv/uv-receipt.json" || fail 'updater receipt has the wrong prefix'
assert_sha256_route
helper=$scenario/home/.local/bin/env
[ -f "$helper" ] || fail 'installer PATH helper is missing'
[ ! -x "$helper" ] || fail 'installer PATH helper stayed executable'
if grep -Eq '^[[:space:]]*exec' "$helper"; then fail 'installer PATH helper kept exec delegation'; fi
# shellcheck disable=SC2016
grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$helper" || fail 'installer PATH helper lost its PATH block'
# shellcheck disable=SC2016
[ "$(sh -c '. "$1"; printf sourced' sh "$helper")" = sourced ] ||
    fail 'sourcing the PATH helper replaced the shell'
grep -Fxq owner "$scenario/home/.zshrc" || fail 'standalone uv changed .zshrc'
test ! -e "$scenario/home/.zshenv" || fail 'standalone uv created a shell startup file'
cmp "$scenario/project-before" "$scenario/home/project/.python-version"
if grep -Fq python "$scenario/calls"; then fail 'uv python was invoked'; fi

# A healthy managed installation self-updates without re-downloading the installer.
: > "$scenario/calls"
( PLASTICINE_TEST_UV_LATEST=0.13.2 apply_case > "$scenario/out" )
grep -Fxq 'self update' "$scenario/calls" || fail 'healthy managed uv did not self-update'
if grep -Fxq download "$scenario/calls"; then fail 'rerun executed the installer'; fi
[ "$(cat "$scenario/home/.local/bin/uv.version")" = 0.13.2 ] || fail 'self update did not advance uv'
[ "$(cat "$scenario/home/.local/bin/uvx.version")" = 0.13.2 ] || fail 'self update did not advance uvx'

# A helper that already matches the installer shape is left byte-for-byte alone.
new_case healthy-helper
( PLASTICINE_TEST_UV_ENV_HELPER=stock apply_case >/dev/null )
cmp "$test_root/env.stock" "$scenario/home/.local/bin/env" || fail 'healthy PATH helper was rewritten'

# The reviewed installer route writes no helper at all; nothing may be created.
new_case no-helper
( PLASTICINE_TEST_UV_ENV_HELPER=none apply_case >/dev/null )
test ! -e "$scenario/home/.local/bin/env" || fail 'a missing PATH helper was created'

# A missing uvx, missing receipt, or foreign receipt prefix repairs via the installer.
for repair in uvx receipt prefix; do
    new_case "repair-$repair"
    seed_managed
    case $repair in
        uvx) rm "$scenario/home/.local/bin/uvx" "$scenario/home/.local/bin/uvx.version" ;;
        receipt) rm "$scenario/home/.config/uv/uv-receipt.json" ;;
        prefix) printf '%s\n' '{"install_prefix":"/somewhere/else"}' > "$scenario/home/.config/uv/uv-receipt.json" ;;
    esac
    apply_case >/dev/null
    grep -Fxq installer "$scenario/calls" || fail "repair-$repair did not use the installer"
    [ -x "$scenario/home/.local/bin/uvx" ] || fail "repair-$repair did not restore uvx"
    grep -Fq "\"install_prefix\":\"$scenario_home/.local/bin\"" \
        "$scenario/home/.config/uv/uv-receipt.json" || fail "repair-$repair kept a foreign receipt"
done

for failure in download installer self-update; do
    new_case "$failure"
    if [ "$failure" = self-update ]; then
        seed_managed
    fi
    printf '%s\n' '[data]' 'tools = ["uv", "git-config"]' > "$scenario/config/chezmoi.toml"
    ( PLASTICINE_TEST_UV_FAIL=$failure expect_failure "$failure" )
    test ! -e "$scenario/home/.gitconfig" || fail 'config was applied after uv preparation failed'
    if [ "$failure" = self-update ]; then
        [ -x "$scenario/home/.local/bin/uv" ] || fail "$failure removed the existing uv"
    else
        test ! -e "$scenario/home/.local/bin/uv" || fail "$failure left a partial uv"
    fi
    apply_case >/dev/null
    test -f "$scenario/home/.gitconfig" || fail "retry after $failure did not complete config"
done

new_case external
cp "$test_root/uv" "$fixture_bin/uv"
printf '%s\n' 0.13.1 > "$fixture_bin/uv.version"
expect_failure 'external uv'
grep -Fq 'external uv' "$scenario/err" || fail 'external uv error is not actionable'
test ! -s "$scenario/calls" || fail 'external uv was invoked'
rm "$fixture_bin/uv" "$fixture_bin/uv.version"

new_case external-uvx
seed_managed
cp "$test_root/uv" "$fixture_bin/uvx"
printf '%s\n' 0.13.1 > "$fixture_bin/uvx.version"
expect_failure 'external uvx'
grep -Fq 'external uvx' "$scenario/err" || fail 'external uvx error is not actionable'
test ! -s "$scenario/calls" || fail 'external uvx was invoked'
rm "$fixture_bin/uvx" "$fixture_bin/uvx.version"

new_case broken
seed_managed
printf '%s\n' '#!/bin/sh' 'echo "uv 0.13.1"' 'exit 1' > "$scenario/home/.local/bin/uv"
chmod 755 "$scenario/home/.local/bin/uv"
cp "$scenario/home/.local/bin/uv" "$scenario/before"
expect_failure 'unhealthy managed uv'
grep -Fq 'unhealthy' "$scenario/err" || fail 'unhealthy uv error is not actionable'
cmp "$scenario/before" "$scenario/home/.local/bin/uv"

new_case prerelease
seed_managed
printf '%s\n' '#!/bin/sh' 'echo "uv 0.13.1-rc1"' > "$scenario/home/.local/bin/uv"
chmod 755 "$scenario/home/.local/bin/uv"
expect_failure 'prerelease managed uv'
grep -Fq 'prerelease' "$scenario/err" || fail 'prerelease uv error is not actionable'

new_case mismatch
seed_managed
printf '%s\n' 0.12.9 > "$scenario/home/.local/bin/uvx.version"
apply_case >/dev/null
grep -Fxq installer "$scenario/calls" || fail 'uv/uvx version mismatch did not repair'

new_case symlink
seed_managed
other=$scenario/other-uv
cp "$test_root/uv" "$other"
printf '%s\n' 0.13.1 > "$scenario/other-uv.version"
rm "$scenario/home/.local/bin/uv"
ln -s "$other" "$scenario/home/.local/bin/uv"
expect_failure 'symlink target'
grep -Fq 'regular file' "$scenario/err" || fail 'symlink target error is not actionable'
[ -L "$scenario/home/.local/bin/uv" ] || fail 'symlink target was replaced'

new_case config-dir
mkdir -p "$scenario/home/.config"
printf '%s\n' not-a-directory > "$scenario/home/.config/uv"
expect_failure 'receipt directory is a file'
grep -Fq 'real directory' "$scenario/err" || fail 'receipt directory error is not actionable'

new_case helper-symlink
mkdir -p "$scenario/home/.local/bin"
ln -s "$test_root/env.stock" "$scenario/home/.local/bin/env"
( PLASTICINE_TEST_UV_ENV_HELPER=none expect_failure 'PATH helper symlink' )
grep -Fq 'regular file' "$scenario/err" || fail 'PATH helper symlink error is not actionable'
[ -L "$scenario/home/.local/bin/env" ] || fail 'PATH helper symlink was replaced'

new_case dry-run
apply_case --dry-run >/dev/null
test ! -s "$scenario/calls" || fail 'dry-run invoked the installer'
test ! -e "$scenario/home/.local/bin" || fail 'dry-run created the installation directory'
printf '%s\n' '[data]' 'tools = []' > "$scenario/config/chezmoi.toml"
apply_case >/dev/null
test ! -s "$scenario/calls" || fail 'unselected uv was probed'

for platform in Linux:x86_64 Linux:arm64 Darwin:x86_64 Darwin:arm64; do
    new_case "${platform%:*}-${platform#*:}"
    ( PLASTICINE_UV_OS=${platform%:*} PLASTICINE_UV_ARCH=${platform#*:} apply_case >/dev/null )
    [ -x "$scenario/home/.local/bin/uv" ] || fail "$platform did not install uv"
done

new_case unsupported-platform
( PLASTICINE_UV_OS=Windows PLASTICINE_UV_ARCH=x86_64 expect_failure 'unsupported platform' )
grep -Fq 'no reviewed route' "$scenario/err" || fail 'unsupported platform error is not actionable'
test ! -s "$scenario/calls" || fail 'unsupported platform reached the installer'

new_case relative-config
( XDG_CONFIG_HOME=relative expect_failure 'relative XDG_CONFIG_HOME' )
grep -Fq 'XDG_CONFIG_HOME must be absolute' "$scenario/err"
test ! -s "$scenario/calls" || fail 'relative XDG_CONFIG_HOME reached the installer'

"$repo_dir/install.sh" --help > "$scenario/help"
grep -Fq -- '--uv' "$scenario/help" || fail 'installer help omits --uv'
set +e
"$repo_dir/install.sh" --uv > "$scenario/out" 2> "$scenario/err"
usage_status=$?
set -e
[ "$usage_status" -eq 2 ] || fail 'standalone --uv did not require -y'

printf '%s\n' 'uv integration tests passed'
