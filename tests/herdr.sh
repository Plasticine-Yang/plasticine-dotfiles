#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi 2>/dev/null || true)}
[ -n "$chezmoi_bin" ] || { printf '%s\n' 'herdr tests require chezmoi.' >&2; exit 1; }
case $chezmoi_bin in /*) ;; */*) chezmoi_bin=$(cd -- "$(dirname -- "$chezmoi_bin")" && pwd -P)/${chezmoi_bin##*/} ;; *) chezmoi_bin=$(command -v "$chezmoi_bin" 2>/dev/null || true) ;; esac
[ -n "$chezmoi_bin" ] && [ -x "$chezmoi_bin" ] || { printf '%s\n' 'herdr tests require chezmoi.' >&2; exit 1; }
root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-herdr-test.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM
fail() { printf 'herdr tests: %s\n' "$1" >&2; exit 1; }

work=$root/work; mkdir -p "$work"
find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$work/" \;
git -C "$work" init -q; git -C "$work" add -A
git -C "$work" -c user.name=test -c user.email=test@example.com commit -qm herdr-test
origin=$root/origin.git; git clone -q --bare "$work" "$origin"
bin=$root/bin; fixture=$root/fixture; mkdir -p "$bin" "$fixture"

write_herdr() {
    fixture_path=$1; fixture_version=$2; fixture_channel=${3:-stable}; mkdir -p "$(dirname -- "$fixture_path")"
    sed "s/@VERSION@/$fixture_version/g; s/@CHANNEL@/$fixture_channel/g" > "$fixture_path" <<'EOF'
#!/bin/sh
case ${1:-} in
    --version) printf '%s\n' 'herdr @VERSION@' ;;
    channel) [ "${2:-}" = show ] || exit 91; printf '%s\n' '@CHANNEL@' ;;
    update)
        printf '%s\n' update >> "$PLASTICINE_TEST_HERDR_COMMANDS"
        [ "$#" -eq 1 ] || exit 92
        case ${PLASTICINE_TEST_HERDR_UPDATE:-ok} in
            ok) cp "$PLASTICINE_TEST_HERDR_PAYLOAD" "$0"; chmod 755 "$0" ;;
            noop) : ;;
            decline) printf '%s\n' 'confirmation required' >&2; exit 2 ;;
        esac ;;
    *) printf '%s\n' "forbidden herdr launch: $*" >> "$PLASTICINE_TEST_HERDR_COMMANDS"; exit 90 ;;
esac
EOF
    chmod 755 "$fixture_path"
}
write_herdr "$fixture/herdr-1.2.3" 1.2.3
write_herdr "$fixture/herdr-1.3.0" 1.3.0
cat > "$fixture/install.sh" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' installer >> "$PLASTICINE_TEST_HERDR_COMMANDS"
[ -n "${HERDR_INSTALL_DIR:-}" ] || exit 81
case ${PLASTICINE_TEST_HERDR_INSTALL:-ok} in fail|checksum) exit 82 ;; esac
mkdir -p "$HERDR_INSTALL_DIR"
cp "$PLASTICINE_TEST_HERDR_PAYLOAD" "$HERDR_INSTALL_DIR/herdr"
chmod 755 "$HERDR_INSTALL_DIR/herdr"
EOF
chmod 755 "$fixture/install.sh"
cat > "$bin/curl" <<'EOF'
#!/bin/sh
output=''; url=''
while [ "$#" -gt 0 ]; do case $1 in -o) output=$2; shift ;; http*) url=$1 ;; esac; shift; done
printf '%s\n' "$url" >> "$PLASTICINE_TEST_HERDR_NETWORK"
case ${PLASTICINE_TEST_HERDR_FAIL:-}:$url in metadata:*latest.json) exit 80 ;; installer:*install.sh) exit 80 ;; esac
case $url in
    *latest.json) printf '{"version":"%s"}\n' "$PLASTICINE_TEST_HERDR_RELEASE" > "$output" ;;
    *install.sh) cp "$PLASTICINE_TEST_HERDR_FIXTURE/install.sh" "$output" ;;
    *) exit 89 ;;
esac
EOF
cat > "$bin/ln" <<'EOF'
#!/bin/sh
if [ "${2##*/}" = herdr ]; then
    case ${PLASTICINE_TEST_HERDR_PUBLISH:-} in race) printf '%s\n' owner > "$2"; exit 1 ;; fail) exit 1 ;; esac
fi
exec /bin/ln "$@"
EOF
cat > "$bin/mktemp" <<'EOF'
#!/bin/sh
result=$(/usr/bin/mktemp "$@") || exit $?
printf '%s\n' "$result"
if [ "${PLASTICINE_TEST_HERDR_PUBLISH:-}" = race ]; then
    case $result in */.local/bin/.herdr.plasticine.*) printf '%s\n' owner > "$PLASTICINE_TEST_HERDR_TARGET" ;; esac
fi
EOF
cat > "$bin/lazygit" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || exit 90
printf '%s\n' 'lazygit fixture'
EOF
chmod +x "$bin"/*

# The real interactive entrypoint exposes Herdr and cancellation performs no
# Herdr network lookup, installer execution, or destination mutation.
if command -v expect >/dev/null 2>&1; then
    cancel=$root/cancel; mkdir -p "$cancel/home"
    export PLASTICINE_TEST_HERDR_INSTALLER="$repo_dir/install.sh" PLASTICINE_TEST_HERDR_CHEZMOI="$chezmoi_bin"
    export PLASTICINE_TEST_HERDR_ORIGIN="$origin" PLASTICINE_TEST_HERDR_CANCEL="$cancel" PLASTICINE_TEST_HERDR_BIN="$bin"
    expect <<'EOF'
set timeout 20
set scenario $env(PLASTICINE_TEST_HERDR_CANCEL)
set env(PLASTICINE_CHEZMOI_BIN) $env(PLASTICINE_TEST_HERDR_CHEZMOI)
set env(PLASTICINE_DOTFILES_REPO_URL) $env(PLASTICINE_TEST_HERDR_ORIGIN)
set env(PLASTICINE_CHEZMOI_SOURCE_DIR) $scenario/source
set env(PLASTICINE_CHEZMOI_CONFIG_FILE) $scenario/config/config.toml
set env(PLASTICINE_CHEZMOI_STATE_FILE) $scenario/config/state
set env(PLASTICINE_CHEZMOI_DEST_DIR) $scenario/home
set env(PLASTICINE_TEST_HERDR_NETWORK) $scenario/network
set env(PATH) "$env(PLASTICINE_TEST_HERDR_BIN):/usr/bin:/bin"
spawn $env(PLASTICINE_TEST_HERDR_INSTALLER)
expect "选择要处理的工具"
send "\033\[B\033\[B"; after 200; send " "; after 200; send "\r"
expect "Previewing Herdr toolchain"
expect "Apply these changes?"
send "n\r"
expect eof
catch wait result
exit [lindex $result 3]
EOF
    grep -Fq 'tools = ["herdr"]' "$cancel/config/config.toml" || fail 'interactive Herdr selection missing'
    [ ! -e "$cancel/network" ] || fail 'cancel queried stable target'
    [ ! -e "$cancel/home/.local" ] || fail 'cancel mutated Herdr destination'
fi

run() {
    scenario=$1; release=$2; shift 2
    mkdir -p "$scenario/home"
    selected_payload=${PLASTICINE_TEST_HERDR_PAYLOAD:-$fixture/herdr-$release}
    HOME="$scenario/home" PATH="$scenario/home/.local/bin:$bin:/usr/bin:/bin" \
    PLASTICINE_CHEZMOI_BIN="$chezmoi_bin" PLASTICINE_DOTFILES_REPO_URL="$origin" \
    PLASTICINE_CHEZMOI_SOURCE_DIR="$scenario/source" PLASTICINE_CHEZMOI_CONFIG_FILE="$scenario/config/config.toml" \
    PLASTICINE_CHEZMOI_STATE_FILE="$scenario/config/state" PLASTICINE_CHEZMOI_DEST_DIR="$scenario/home" \
    PLASTICINE_TEST_HERDR_FIXTURE="$fixture" PLASTICINE_TEST_HERDR_RELEASE="$release" \
    PLASTICINE_TEST_HERDR_PAYLOAD="$selected_payload" \
    PLASTICINE_TEST_HERDR_NETWORK="$scenario/network" PLASTICINE_TEST_HERDR_COMMANDS="$scenario/commands" \
    PLASTICINE_TEST_HERDR_TARGET="$scenario/home/.local/bin/herdr" \
    PLASTICINE_TEST_HERDR_UPDATE=${PLASTICINE_TEST_HERDR_UPDATE:-ok} \
    PLASTICINE_TEST_HERDR_INSTALL=${PLASTICINE_TEST_HERDR_INSTALL:-ok} \
    PLASTICINE_TEST_HERDR_FAIL=${PLASTICINE_TEST_HERDR_FAIL:-} \
    PLASTICINE_TEST_HERDR_PUBLISH=${PLASTICINE_TEST_HERDR_PUBLISH:-} \
        "$repo_dir/install.sh" -y --herdr "$@"
}

# Missing installation uses the downloaded official script in private staging,
# publishes safely, and converges without shell/config/session effects.
s=$root/missing; run "$s" 1.2.3 > "$s.out"
[ "$("$s/home/.local/bin/herdr" --version)" = 'herdr 1.2.3' ] || fail 'missing install did not reach target'
[ "$(grep -Fc installer "$s/commands")" -eq 1 ] || fail 'official installer was not used exactly once'
grep -Fq 'action=install' "$s.out" || fail 'install result missing'
[ ! -e "$s/home/.zshrc" ] || fail 'standalone selection edited shell'
mkdir -p "$s/home/.config/herdr"; printf session > "$s/home/.config/herdr/session"
: > "$s/network"; : > "$s/commands"; run "$s" 1.2.3 > "$s.current"
[ "$(wc -l < "$s/network" | tr -d ' ')" -eq 1 ] || fail 'current install downloaded installer/assets'
[ ! -s "$s/commands" ] || fail 'current install invoked updater or launch'
[ "$(cat "$s/home/.config/herdr/session")" = session ] || fail 'native state changed'

# A later stable target uses only the direct native updater and verifies it.
: > "$s/network"; : > "$s/commands"; PLASTICINE_TEST_HERDR_PAYLOAD=$fixture/herdr-1.3.0 run "$s" 1.3.0 > "$s.update"
unset PLASTICINE_TEST_HERDR_PAYLOAD
[ "$("$s/home/.local/bin/herdr" --version)" = 'herdr 1.3.0' ] || fail 'native update did not converge'
[ "$(cat "$s/commands")" = update ] || fail 'unexpected command or missing native update'

# Failures do not claim currency or apply combined configuration.
for mode in noop decline; do
    f=$root/$mode; mkdir -p "$f/home/.local/bin"; write_herdr "$f/home/.local/bin/herdr" 1.2.3
    if PLASTICINE_TEST_HERDR_UPDATE=$mode PLASTICINE_TEST_HERDR_PAYLOAD=$fixture/herdr-1.3.0 run "$f" 1.3.0 --lazygit >"$f.out" 2>"$f.err"; then fail "$mode update succeeded"; fi
    [ "$("$f/home/.local/bin/herdr" --version)" = 'herdr 1.2.3' ] || fail "$mode changed version unexpectedly"
    [ ! -e "$f/home/.zshrc" ] || fail "$mode applied combined configuration"
done

# External current is accepted; external outdated is actionable and never shadowed.
for state in current outdated; do
    e=$root/external-$state; mkdir -p "$e/home" "$e/external"
    case $state in current) version=1.3.0 ;; outdated) version=1.2.3 ;; esac
    write_herdr "$e/external/herdr" "$version"
    if HOME="$e/home" PATH="$e/external:$bin:/usr/bin:/bin" PLASTICINE_CHEZMOI_BIN="$chezmoi_bin" \
      PLASTICINE_DOTFILES_REPO_URL="$origin" PLASTICINE_CHEZMOI_SOURCE_DIR="$e/source" \
      PLASTICINE_CHEZMOI_CONFIG_FILE="$e/config/config.toml" PLASTICINE_CHEZMOI_STATE_FILE="$e/config/state" \
      PLASTICINE_CHEZMOI_DEST_DIR="$e/home" PLASTICINE_TEST_HERDR_FIXTURE="$fixture" \
      PLASTICINE_TEST_HERDR_RELEASE=1.3.0 PLASTICINE_TEST_HERDR_PAYLOAD="$fixture/herdr-1.3.0" \
      PLASTICINE_TEST_HERDR_NETWORK="$e/network" PLASTICINE_TEST_HERDR_COMMANDS="$e/commands" \
      "$repo_dir/install.sh" -y --herdr >"$e.out" 2>"$e.err"; then rc=0; else rc=$?; fi
    case $state in current) [ "$rc" -eq 0 ] || fail 'current external owner rejected' ;; outdated) [ "$rc" -ne 0 ] || fail 'outdated external owner accepted' ;; esac
    [ ! -e "$e/home/.local/bin/herdr" ] || fail 'external owner was shadowed'
done

# Custom channel, unhealthy executable, metadata/installer/publication failures.
p=$root/preview; mkdir -p "$p/home/.local/bin"; write_herdr "$p/home/.local/bin/herdr" 1.2.3-preview.1 preview
if run "$p" 1.3.0 >/dev/null 2>"$p.err"; then fail 'preview channel accepted'; fi
grep -Fq 'prerelease/custom' "$p.err" || fail 'preview guidance missing'
channel=$root/channel; mkdir -p "$channel/home/.local/bin"; write_herdr "$channel/home/.local/bin/herdr" 1.3.0 preview
if run "$channel" 1.3.0 >/dev/null 2>"$channel.err"; then fail 'current preview channel accepted'; fi
grep -Fq "uses channel 'preview'" "$channel.err" || { /bin/cat "$channel.err" >&2; fail 'channel guidance missing'; }
unhealthy=$root/unhealthy; mkdir -p "$unhealthy/home/.local/bin"
printf '%s\n' '#!/bin/sh' 'exit 7' > "$unhealthy/home/.local/bin/herdr"; chmod 755 "$unhealthy/home/.local/bin/herdr"
if run "$unhealthy" 1.3.0 >/dev/null 2>"$unhealthy.err"; then fail 'unhealthy command accepted'; fi
grep -Fq 'unhealthy and was left untouched' "$unhealthy.err" || fail 'unhealthy guidance missing'
for failure in metadata installer install publication race; do
    f=$root/fail-$failure; mkdir -p "$f/home"
    PLASTICINE_TEST_HERDR_PAYLOAD=$fixture/herdr-1.2.3
    export PLASTICINE_TEST_HERDR_PAYLOAD
    case $failure in
      metadata) PLASTICINE_TEST_HERDR_FAIL=metadata; export PLASTICINE_TEST_HERDR_FAIL ;;
      installer) PLASTICINE_TEST_HERDR_FAIL=installer; export PLASTICINE_TEST_HERDR_FAIL ;;
      install) PLASTICINE_TEST_HERDR_INSTALL=checksum; export PLASTICINE_TEST_HERDR_INSTALL ;;
      publication) PLASTICINE_TEST_HERDR_PUBLISH=fail; export PLASTICINE_TEST_HERDR_PUBLISH ;;
      race) PLASTICINE_TEST_HERDR_PUBLISH=race; export PLASTICINE_TEST_HERDR_PUBLISH ;;
    esac
    if run "$f" 1.2.3 >/dev/null 2>"$f.err"; then fail "$failure succeeded"; fi
    case $failure in
      race)
        if [ ! -f "$f/home/.local/bin/herdr" ] || [ "$(/bin/cat "$f/home/.local/bin/herdr")" != owner ]; then
            /bin/cat "$f.err" >&2
            fail 'raced owner removed'
        fi ;;
      *) [ ! -e "$f/home/.local/bin/herdr" ] || fail "$failure published command" ;;
    esac
    unset PLASTICINE_TEST_HERDR_FAIL PLASTICINE_TEST_HERDR_INSTALL PLASTICINE_TEST_HERDR_PUBLISH PLASTICINE_TEST_HERDR_PAYLOAD
done

printf '%s\n' 'herdr tests passed'
