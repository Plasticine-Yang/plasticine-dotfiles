#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi 2>/dev/null || true)}
[ -n "$chezmoi_bin" ] || { printf '%s\n' 'CHEZMOI_BIN or chezmoi is required.' >&2; exit 1; }
case $chezmoi_bin in
    /*) ;;
    */*) chezmoi_bin=$(cd -- "$(dirname -- "$chezmoi_bin")" && pwd -P)/${chezmoi_bin##*/} ;;
    *) chezmoi_bin=$(command -v "$chezmoi_bin" 2>/dev/null || true) ;;
esac
[ -n "$chezmoi_bin" ] && [ -x "$chezmoi_bin" ] || { printf '%s\n' 'CHEZMOI_BIN or chezmoi is required.' >&2; exit 1; }
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-fnm-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'fnm test: %s\n' "$1" >&2; exit 1; }

fixture_bin=$test_root/bin
mkdir -p "$fixture_bin"
cat > "$fixture_bin/curl" <<'EOF'
#!/bin/sh
out=''
while [ "$#" -gt 0 ]; do case $1 in -o) out=$2; shift ;; esac; shift; done
[ -n "$out" ] || exit 98
[ "${PLASTICINE_TEST_FNM_DOWNLOAD_FAIL:-0}" != 1 ] || exit 22
cat > "$out" <<'SCRIPT'
#!/bin/sh
set -eu
install_dir=''
skip=0
while [ "$#" -gt 0 ]; do
  case $1 in --skip-shell) skip=1 ;; --install-dir) install_dir=$2; shift ;; --release*) exit 91 ;; esac
  shift
done
[ "$skip" -eq 1 ] && [ -n "$install_dir" ] || exit 92
[ "${PLASTICINE_TEST_FNM_SCRIPT_FAIL:-0}" != 1 ] || exit 93
mkdir -p "$install_dir"
cat > "$install_dir/fnm" <<BIN
#!/bin/sh
case \${1:-} in --version) printf '%s\n' 'fnm ${PLASTICINE_TEST_FNM_LATEST:-1.38.1}' ;; env) printf '%s\n' 'typeset -g PLASTICINE_FNM_ACTIVE=1' ;; *) exit 94 ;; esac
BIN
chmod +x "$install_dir/fnm"
SCRIPT
chmod +x "$out"
EOF
chmod +x "$fixture_bin/curl"

write_config() { mkdir -p "$1"; printf '%s\n' '[data]' 'tools = ["fnm"]' > "$1/chezmoi.toml"; }
apply_linux() {
    scenario=$1; shift
    PATH=$fixture_bin:/usr/bin:/bin \
    PLASTICINE_FNM_OS=Linux PLASTICINE_FNM_ARCH=x86_64 \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home \
    "$chezmoi_bin" -S "$repo_dir" -D "$scenario/home" -c "$scenario/config/chezmoi.toml" \
      --persistent-state "$scenario/state" apply --no-tty "$@"
}

linux=$test_root/linux
mkdir -p "$linux/home/.local/share/fnm"
write_config "$linux/config"
printf 'node-state\n' > "$linux/home/.local/share/fnm/sentinel"
printf 'owner-zshrc\n' > "$linux/home/.zshrc"
PLASTICINE_TEST_FNM_LATEST=1.38.1 apply_linux "$linux" >/dev/null
[ "$("$linux/home/.local/bin/fnm" --version)" = 'fnm 1.38.1' ] || fail 'Linux install target mismatch'
[ "$(cat "$linux/home/.zshrc")" = owner-zshrc ] || fail 'standalone selection edited .zshrc'
[ "$(cat "$linux/home/.local/share/fnm/sentinel")" = node-state ] || fail 'runtime state changed'
before=$(cksum "$linux/home/.local/bin/fnm")
PLASTICINE_TEST_FNM_LATEST=1.38.1 apply_linux "$linux" >/dev/null
[ "$(cksum "$linux/home/.local/bin/fnm")" = "$before" ] || fail 'current target was replaced'
PLASTICINE_TEST_FNM_LATEST=1.39.0 apply_linux "$linux" >/dev/null
[ "$("$linux/home/.local/bin/fnm" --version)" = 'fnm 1.39.0' ] || fail 'next invocation did not update'

preserve=$test_root/preserve
mkdir -p "$preserve/home/.local/bin"
write_config "$preserve/config"
cp "$linux/home/.local/bin/fnm" "$preserve/home/.local/bin/fnm"
if PLASTICINE_TEST_FNM_LATEST=1.40.0 PLASTICINE_TEST_FNM_SCRIPT_FAIL=1 apply_linux "$preserve" >/dev/null 2>&1; then fail 'script failure succeeded'; fi
[ "$("$preserve/home/.local/bin/fnm" --version)" = 'fnm 1.39.0' ] || fail 'failed candidate replaced working fnm'

dry=$test_root/dry
mkdir -p "$dry/home"
write_config "$dry/config"
marker=$dry/network
cat > "$dry/curl" <<EOF
#!/bin/sh
printf network > '$marker'
exit 99
EOF
chmod +x "$dry/curl"
PATH=$dry:$fixture_bin:/usr/bin:/bin PLASTICINE_FNM_OS=Linux PLASTICINE_FNM_ARCH=x86_64 \
  PLASTICINE_CHEZMOI_DEST_DIR=$dry/home "$chezmoi_bin" -S "$repo_dir" -D "$dry/home" -c "$dry/config/chezmoi.toml" \
  --persistent-state "$dry/state" apply --dry-run --no-tty >/dev/null
[ ! -e "$marker" ] && [ ! -e "$dry/home/.local" ] || fail 'dry-run queried or mutated fnm'

external=$test_root/external
mkdir -p "$external/home" "$external/bin"
write_config "$external/config"
cat > "$external/bin/fnm" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && printf '%s\n' 'fnm 1.0.0'
EOF
chmod +x "$external/bin/fnm"
if PATH=$external/bin:$fixture_bin:/usr/bin:/bin PLASTICINE_FNM_OS=Linux PLASTICINE_FNM_ARCH=x86_64 \
  PLASTICINE_TEST_FNM_LATEST=1.38.1 PLASTICINE_CHEZMOI_DEST_DIR=$external/home \
  "$chezmoi_bin" -S "$repo_dir" -D "$external/home" -c "$external/config/chezmoi.toml" --persistent-state "$external/state" apply --no-tty >/dev/null 2>&1; then
  fail 'outdated external owner was taken over'
fi
[ ! -e "$external/home/.local/bin/fnm" ] || fail 'external owner created shadow copy'

brew=$test_root/brew
mkdir -p "$brew/home" "$brew/prefix/bin" "$brew/bin"
write_config "$brew/config"
cat > "$brew/bin/brew" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$PLASTICINE_TEST_BREW_CALLS"
case $1 in
 --version|update) exit 0 ;;
 info) printf '%s\n' '{"formulae":[{"versions":{"stable":"1.38.1"}}]}' ;;
 --prefix) printf '%s\n' "$PLASTICINE_TEST_BREW_PREFIX" ;;
 install|upgrade)
   cat > "$PLASTICINE_TEST_BREW_PREFIX/bin/fnm" <<'BIN'
#!/bin/sh
[ "${1:-}" = --version ] && printf '%s\n' 'fnm 1.38.1'
BIN
   chmod +x "$PLASTICINE_TEST_BREW_PREFIX/bin/fnm" ;;
 *) exit 97 ;;
esac
EOF
chmod +x "$brew/bin/brew"
: > "$brew/calls"
PATH=$brew/bin:$fixture_bin:/usr/bin:/bin PLASTICINE_FNM_OS=Darwin PLASTICINE_FNM_ARCH=arm64 \
  PLASTICINE_TEST_BREW_CALLS=$brew/calls PLASTICINE_TEST_BREW_PREFIX=$brew/prefix \
  PLASTICINE_CHEZMOI_DEST_DIR=$brew/home "$chezmoi_bin" -S "$repo_dir" -D "$brew/home" -c "$brew/config/chezmoi.toml" \
  --persistent-state "$brew/state" apply --no-tty >/dev/null
grep -Fxq update "$brew/calls" || fail 'Homebrew metadata was not refreshed'
grep -Fxq 'install fnm' "$brew/calls" || fail 'Homebrew did not install only fnm'
[ ! -e "$brew/home/.local/bin/fnm" ] || fail 'macOS route published a shadow binary'

printf '%s\n' 'fnm route tests passed'
