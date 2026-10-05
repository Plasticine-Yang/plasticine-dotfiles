#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
case $chezmoi_bin in /*) ;; *) chezmoi_bin=$(command -v "$chezmoi_bin") ;; esac
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-rust-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'rust test: %s\n' "$1" >&2; exit 1; }
unset CARGO_HOME RUSTUP_HOME RUSTUP_TOOLCHAIN
fixture_bin=$test_root/bin
mkdir -p "$fixture_bin"

cat > "$test_root/rustup" <<'FIXTURE'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$PLASTICINE_TEST_RUST_CALLS"
[ "${RUSTUP_TOOLCHAIN:-}" = '' ] || exit 90
[ "${PLASTICINE_TEST_RUST_FAIL:-}" != "$1-${2:-}" ] || exit 91
case $1 in
    --version) printf '%s\n' 'rustup 1.28.2 (fixture)'; exit 0 ;;
    default)
        if [ "$#" -gt 1 ]; then printf '%s\n' "$2" > "$RUSTUP_HOME/.test-default"; exit 0; fi
        current=$(cat "$RUSTUP_HOME/.test-default" 2>/dev/null || printf none)
        if [ "$current" = none ]; then printf '%s\n' 'error: no default toolchain is configured' >&2; exit 1; fi
        printf '%s (default)\n' "$current" ;;
    self) [ "$*" = 'self update' ] ;;
    toolchain)
        [ "$*" = 'toolchain install stable --profile minimal --component rustfmt --component clippy --no-self-update' ] || exit 92
        mkdir -p "$RUSTUP_HOME/toolchains/stable/bin"
        for tool in rustc cargo rustfmt clippy-driver; do
            cat > "$RUSTUP_HOME/toolchains/stable/bin/$tool" <<BIN
#!/bin/sh
printf '%s\\n' '$tool ${PLASTICINE_TEST_RUST_LATEST:-1.90.0}'
BIN
            chmod 755 "$RUSTUP_HOME/toolchains/stable/bin/$tool"
        done
        current=$(cat "$RUSTUP_HOME/.test-default" 2>/dev/null || printf none)
        [ "$current" != none ] || printf '%s\n' stable-fixture > "$RUSTUP_HOME/.test-default" ;;
    run)
        [ "$2" = stable ] && [ "$4" = --version ] || exit 93
        [ "${PLASTICINE_TEST_RUST_FAIL:-}" != "verify-$3" ] || exit 94
        exec "$RUSTUP_HOME/toolchains/stable/bin/$3" "$4" ;;
    *) exit 95 ;;
esac
FIXTURE
chmod 755 "$test_root/rustup"
cat > "$fixture_bin/curl" <<'CURL'
#!/bin/sh
set -eu
out=''; url=''
while [ "$#" -gt 0 ]; do case $1 in -o) out=$2; shift ;; https:*) url=$1 ;; esac; shift; done
[ "$url" = https://sh.rustup.rs ] && [ -n "$out" ] || exit 96
printf '%s\n' download >> "$PLASTICINE_TEST_RUST_CALLS"
[ "${PLASTICINE_TEST_RUST_FAIL:-}" != download ] || exit 22
cat > "$out" <<'INSTALLER'
#!/bin/sh
set -eu
[ "$*" = '-y --no-modify-path --default-toolchain none --profile minimal' ] || exit 97
printf '%s\n' install >> "$PLASTICINE_TEST_RUST_CALLS"
[ "${PLASTICINE_TEST_RUST_FAIL:-}" != installer ] || exit 98
mkdir -p "$CARGO_HOME/bin" "$RUSTUP_HOME"
cp "$PLASTICINE_TEST_RUST_TEMPLATE" "$CARGO_HOME/bin/rustup"
INSTALLER
CURL
chmod 755 "$fixture_bin/curl"

new_case() {
    scenario=$test_root/$1
    mkdir -p "$scenario/home" "$scenario/config"
    printf '%s\n' '[data]' 'tools = ["rust"]' > "$scenario/config/chezmoi.toml"
    : > "$scenario/calls"
}
apply_case() {
    PATH=$fixture_bin:/usr/bin:/bin HOME=$scenario/home \
    PLASTICINE_TEST_RUST_CALLS=$scenario/calls PLASTICINE_TEST_RUST_TEMPLATE=$test_root/rustup \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home \
        "$chezmoi_bin" -S "$repo_dir" -D "$scenario/home" -c "$scenario/config/chezmoi.toml" \
        --persistent-state "$scenario/state" apply --no-tty "$@"
}
expect_failure() {
    if apply_case > "$scenario/out" 2> "$scenario/err"; then fail "$1 was accepted"; fi
}
seed_native() {
    mkdir -p "$scenario/home/.cargo/bin" "$scenario/home/.rustup"
    cp "$test_root/rustup" "$scenario/home/.cargo/bin/rustup"
    printf '%s\n' "$1" > "$scenario/home/.rustup/.test-default"
}

new_case fresh
printf '%s\n' owner > "$scenario/home/.zshrc"
mkdir -p "$scenario/home/project"
printf '%s\n' '[toolchain]' 'channel = "nightly"' > "$scenario/home/project/rust-toolchain.toml"
cp "$scenario/home/project/rust-toolchain.toml" "$scenario/project-before"
apply_case > "$scenario/out"
grep -Fxq install "$scenario/calls" || fail 'missing rustup was not installed'
grep -Fxq 'default stable' "$scenario/calls" || fail 'fresh install did not default to stable'
grep -Fxq owner "$scenario/home/.zshrc" || fail 'standalone Rust changed .zshrc'
cmp "$scenario/project-before" "$scenario/home/project/rust-toolchain.toml"
: > "$scenario/calls"
PLASTICINE_TEST_RUST_LATEST=1.91.0 apply_case > "$scenario/out"
grep -Fxq 'self update' "$scenario/calls" || fail 'rerun did not maintain rustup'
if grep -Fxq download "$scenario/calls"; then fail 'rerun executed bootstrap'; fi
grep -Fq 'rustc 1.91.0' "$scenario/out" || fail 'rerun did not maintain stable'

# Native stable maintenance must not follow an environment/project override or
# change the default, other toolchains, Cargo settings, or native home layout.
new_case preserve
seed_native nightly-fixture
mkdir -p "$scenario/home/.rustup/toolchains/nightly" "$scenario/home/project"
printf '%s\n' nightly-state > "$scenario/home/.rustup/toolchains/nightly/sentinel"
printf '%s\n' owner-settings > "$scenario/home/.rustup/settings.toml"
printf '%s\n' '[net]' 'offline = true' > "$scenario/home/.cargo/config.toml"
cp "$scenario/home/.cargo/config.toml" "$scenario/cargo-before"
printf '%s\n' '[toolchain]' 'channel = "nightly"' > "$scenario/home/project/rust-toolchain.toml"
(cd "$scenario/home/project" && RUSTUP_TOOLCHAIN=nightly apply_case) >/dev/null
[ "$(cat "$scenario/home/.rustup/.test-default")" = nightly-fixture ] || fail 'existing default was changed'
grep -Fxq nightly-state "$scenario/home/.rustup/toolchains/nightly/sentinel"
grep -Fxq owner-settings "$scenario/home/.rustup/settings.toml"
cmp "$scenario/cargo-before" "$scenario/home/.cargo/config.toml"
if grep -Eq '^default (stable|nightly)' "$scenario/calls"; then fail 'existing default was reset'; fi

new_case explicit-none
seed_native none
apply_case >/dev/null
[ "$(cat "$scenario/home/.rustup/.test-default")" = none ] || fail 'explicit no-default setting was lost'

new_case custom-homes
cargo_native=$scenario/custom\ cargo
rustup_native=$scenario/custom\ rustup
CARGO_HOME=$cargo_native RUSTUP_HOME=$rustup_native apply_case >/dev/null
[ -x "$cargo_native/bin/rustup" ] && [ -x "$rustup_native/toolchains/stable/bin/rustc" ] || fail 'custom native homes were ignored'
[ ! -e "$scenario/home/.cargo" ] && [ ! -e "$scenario/home/.rustup" ] || fail 'custom homes were relocated'
CARGO_HOME=$cargo_native RUSTUP_HOME=$rustup_native apply_case >/dev/null

new_case dry-run
apply_case --dry-run >/dev/null
test ! -s "$scenario/calls" || fail 'dry-run invoked Rust maintenance'
test ! -e "$scenario/home/.cargo"
printf '%s\n' '[data]' 'tools = []' > "$scenario/config/chezmoi.toml"
apply_case >/dev/null
test ! -s "$scenario/calls" || fail 'unselected Rust was probed'

for platform in Linux:x86_64 Linux:arm64 Darwin:x86_64 Darwin:arm64; do
    new_case "$platform"
    PLASTICINE_RUST_OS=${platform%:*} PLASTICINE_RUST_ARCH=${platform#*:} apply_case >/dev/null
    test -x "$scenario/home/.cargo/bin/rustup"
done

for failure in download installer; do
    new_case "$failure"
    printf '%s\n' '[data]' 'tools = ["rust", "git-config"]' > "$scenario/config/chezmoi.toml"
    PLASTICINE_TEST_RUST_FAIL=$failure expect_failure "$failure"
    test ! -e "$scenario/home/.cargo/bin/rustup"
    test ! -e "$scenario/home/.gitconfig" || fail 'config was applied after Rust preparation failed'
    apply_case >/dev/null
    test -f "$scenario/home/.gitconfig" || fail 'retry did not complete config'
done
for failure in self-update toolchain-install verify-rustc verify-cargo verify-rustfmt verify-clippy-driver; do
    new_case "$failure"
    seed_native nightly-fixture
    printf '%s\n' '[data]' 'tools = ["rust", "git-config"]' > "$scenario/config/chezmoi.toml"
    PLASTICINE_TEST_RUST_FAIL=$failure expect_failure "$failure"
    test -x "$scenario/home/.cargo/bin/rustup"
    test ! -e "$scenario/home/.gitconfig" || fail 'config was applied after native failure'
    [ "$(cat "$scenario/home/.rustup/.test-default")" = nightly-fixture ] || fail 'failed native maintenance changed default'
    apply_case >/dev/null
    test -f "$scenario/home/.gitconfig" || fail 'native failure could not be retried'
done

new_case external
cp "$test_root/rustup" "$fixture_bin/rustup"
expect_failure external
grep -Fq 'external rustup' "$scenario/err"
test ! -s "$scenario/calls" || fail 'external owner was invoked'
rm "$fixture_bin/rustup"
for command in cargo rustc; do
    new_case "external-$command"
    printf '%s\n' '#!/bin/sh' 'exit 99' > "$fixture_bin/$command"
    chmod 755 "$fixture_bin/$command"
    expect_failure "external $command"
    test ! -s "$scenario/calls"
    rm "$fixture_bin/$command"
done
new_case broken
seed_native none
printf '%s\n' '#!/bin/sh' 'echo "rustup 1.28.2"' 'exit 1' > "$scenario/home/.cargo/bin/rustup"
expect_failure unhealthy
new_case symlink
mkdir -p "$scenario/other"
ln -s "$scenario/other" "$scenario/home/.cargo"
expect_failure 'symlink native home'
new_case orphan-proxy
mkdir -p "$scenario/home/.cargo/bin"
printf '%s\n' 'independent cargo' > "$scenario/home/.cargo/bin/cargo"
expect_failure 'orphan proxy'
grep -Fxq 'independent cargo' "$scenario/home/.cargo/bin/cargo"
new_case orphan-settings
mkdir -p "$scenario/home/.rustup"
printf '%s\n' 'default_toolchain = "nightly"' > "$scenario/home/.rustup/settings.toml"
expect_failure 'orphan rustup settings'
test ! -s "$scenario/calls" || fail 'orphan settings were passed to a fresh installer'
grep -Fxq 'default_toolchain = "nightly"' "$scenario/home/.rustup/settings.toml"
new_case relative-home
CARGO_HOME=relative expect_failure 'relative Cargo home'
test ! -s "$scenario/calls"

new_case invalid-default
seed_native nightly-fixture
# The generated executable expands its own argument.
# shellcheck disable=SC2016
printf '%s\n' '#!/bin/sh' 'case $1 in --version) echo "rustup 1.28.2" ;; *) exit 1 ;; esac' > "$scenario/home/.cargo/bin/rustup"
expect_failure 'unreadable default settings'
grep -Fq 'could not read the existing default toolchain' "$scenario/err"

"$repo_dir/install.sh" --help > "$scenario/help"
grep -Fq -- '--rust' "$scenario/help"
set +e
"$repo_dir/install.sh" --rust > "$scenario/out" 2> "$scenario/err"
usage_status=$?
set -e
[ "$usage_status" -eq 2 ] || fail 'standalone --rust did not require -y'

printf '%s\n' 'Rust native route integration tests passed'
