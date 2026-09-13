#!/bin/sh
set -eu

# Normal scenarios exercise the default managed Neovim location. Explicit
# rejection cases below reintroduce each unsupported override independently.
unset NVIM_APPNAME XDG_CONFIG_HOME

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi 2>/dev/null || true)}
[ -n "$chezmoi_bin" ] || { printf '%s\n' 'neovim tests require chezmoi.' >&2; exit 1; }
case $chezmoi_bin in /*) ;; */*) chezmoi_bin=$(cd -- "$(dirname -- "$chezmoi_bin")" && pwd -P)/${chezmoi_bin##*/} ;; *) chezmoi_bin=$(command -v "$chezmoi_bin" 2>/dev/null || true) ;; esac
[ -n "$chezmoi_bin" ] && [ -x "$chezmoi_bin" ] || { printf '%s\n' 'neovim tests require chezmoi.' >&2; exit 1; }
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-neovim-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
for override in nvim-appname xdg-config-home; do
    override_root=$test_root/reject-$override
    mkdir -p "$override_root/home"
    case $override in
        nvim-appname) override_env=NVIM_APPNAME=host-nvim ;;
        xdg-config-home) override_env=XDG_CONFIG_HOME=/tmp/host-config ;;
    esac
    if env "$override_env" HOME="$override_root/home" \
        PLASTICINE_CHEZMOI_BIN="$chezmoi_bin" \
        PLASTICINE_CHEZMOI_SOURCE_DIR="$override_root/source" \
        PLASTICINE_CHEZMOI_CONFIG_FILE="$override_root/config/chezmoi.toml" \
        PLASTICINE_CHEZMOI_STATE_FILE="$override_root/config/chezmoistate.boltdb" \
        PLASTICINE_CHEZMOI_DEST_DIR="$override_root/home" \
        "$repo_dir/install.sh" -y --neovim >"$override_root/out" 2>"$override_root/err"; then
        printf 'unsupported Neovim environment was accepted: %s\n' "$override" >&2
        exit 1
    fi
    grep -Fq 'NVIM_APPNAME and XDG_CONFIG_HOME are unsupported' "$override_root/err"
    [ ! -e "$override_root/source" ] && [ ! -e "$override_root/config" ]
done
config=$test_root/chezmoi.toml
PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS=neovim \
    "$chezmoi_bin" -S "$repo_dir" -D "$test_root/home" --persistent-state "$test_root/state" init -C "$config" >/dev/null
grep -Fq 'tools = ["neovim"]' "$config"

fixture_bin=$test_root/bin
fixture_assets=$test_root/assets
mkdir -p "$fixture_bin" "$fixture_assets"
make_archive() {
    version=$1
    root=$test_root/build-$version/nvim-linux-x86_64
    mkdir -p "$root/bin" "$root/share/nvim/runtime"
    cat > "$root/bin/nvim" <<EOF
#!/bin/sh
case "\${1:-}" in
  --version) printf '%s\n' 'NVIM v$version' ;;
  --clean) exit 0 ;;
  --headless)
    [ "\${PLASTICINE_NEOVIM_FAIL_HEADLESS:-0}" != 1 ] || exit 42
    [ -z "\${PLASTICINE_NEOVIM_TEST_CALLS:-}" ] || printf 'nvim %s\n' "\$*" >> "\$PLASTICINE_NEOVIM_TEST_CALLS"
    ;;
  *) exit 99 ;;
esac
EOF
    chmod 755 "$root/bin/nvim"
    printf '%s\n' '-- packaged runtime sentinel' > "$root/share/nvim/runtime/filetype.lua"
    tar -czf "$fixture_assets/$version.tar.gz" -C "$test_root/build-$version" nvim-linux-x86_64
    shasum -a 256 "$fixture_assets/$version.tar.gz" | awk '{print $1}' > "$fixture_assets/$version.sha"
}
make_archive 0.12.4
make_archive 0.12.5
unsafe_root=$test_root/unsafe/nvim-linux-x86_64
mkdir -p "$unsafe_root/bin" "$unsafe_root/share/nvim/runtime"
cp "$test_root/build-0.12.4/nvim-linux-x86_64/bin/nvim" "$unsafe_root/bin/nvim"
cp "$test_root/build-0.12.4/nvim-linux-x86_64/share/nvim/runtime/filetype.lua" "$unsafe_root/share/nvim/runtime/filetype.lua"
ln -s /tmp/escape "$unsafe_root/share/nvim/runtime/unsafe-link"
tar -czf "$fixture_assets/symlink.tar.gz" -C "$test_root/unsafe" nvim-linux-x86_64
rm "$unsafe_root/share/nvim/runtime/unsafe-link"
ln "$unsafe_root/share/nvim/runtime/filetype.lua" "$unsafe_root/share/nvim/runtime/unsafe-hardlink"
tar -czf "$fixture_assets/hardlink.tar.gz" -C "$test_root/unsafe" nvim-linux-x86_64
printf '%s\n' 'not an archive' > "$fixture_assets/malformed.tar.gz"
for archive in symlink hardlink malformed; do
    shasum -a 256 "$fixture_assets/$archive.tar.gz" | awk '{print $1}' > "$fixture_assets/$archive.sha"
done
cat > "$fixture_bin/tar" <<'EOF'
#!/bin/sh
case $* in *-xzf*) [ "${PLASTICINE_NEOVIM_FAIL_EXTRACT:-0}" != 1 ] || exit 42 ;; esac
exec /usr/bin/tar "$@"
EOF
cat > "$fixture_bin/ln" <<'EOF'
#!/bin/sh
[ "${PLASTICINE_NEOVIM_FAIL_PUBLICATION:-0}" != 1 ] || {
    for destination do :; done
    case $destination in */.local/opt/neovim) exit 42 ;; esac
}
exec /bin/ln "$@"
EOF
chmod 755 "$fixture_bin/tar" "$fixture_bin/ln"

cat > "$fixture_bin/curl" <<'EOF'
#!/bin/sh
output=
previous=
for argument in "$@"; do
    [ "$previous" != -o ] || output=$argument
    previous=$argument
done
printf '%s\n' curl >> "$PLASTICINE_NEOVIM_TEST_CALLS"
case $* in
  *api.github.com/repos/neovim/neovim/releases/latest*)
    version=${PLASTICINE_NEOVIM_TEST_VERSION:-0.12.4}
    archive=${PLASTICINE_NEOVIM_ARCHIVE_FIXTURE:-$version}
    digest=$(cat "$PLASTICINE_NEOVIM_TEST_ASSETS/$archive.sha")
    [ "${PLASTICINE_NEOVIM_BAD_DIGEST:-0}" != 1 ] || digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    payload="  \"tag_name\": \"v$version\",
  \"name\": \"nvim-linux-x86_64.tar.gz\",
  \"digest\": \"sha256:$digest\",
  \"browser_download_url\": \"https://github.com/neovim/neovim/releases/download/v$version/nvim-linux-x86_64.tar.gz\""
    [ "${PLASTICINE_NEOVIM_BAD_METADATA:-0}" != 1 ] || payload='{"tag_name":"nightly"}'
    if [ -n "$output" ]; then printf '%s\n' "$payload" > "$output"; else printf '%s\n' "$payload"; fi
    ;;
  *github.com/neovim/neovim/releases/download/*)
    [ -z "${PLASTICINE_NEOVIM_RACE_TARGET:-}" ] || mkdir -p "$PLASTICINE_NEOVIM_RACE_TARGET"
    archive=${PLASTICINE_NEOVIM_ARCHIVE_FIXTURE:-${PLASTICINE_NEOVIM_TEST_VERSION:-0.12.4}}
    cp "$PLASTICINE_NEOVIM_TEST_ASSETS/$archive.tar.gz" "$output"
    ;;
  *) exit 99 ;;
esac
EOF
chmod 755 "$fixture_bin/curl"

apply_case() {
    case_home=$1; case_state=$2; shift 2
    PATH=$fixture_bin:/usr/bin:/bin PLASTICINE_NEOVIM_OS=Linux PLASTICINE_NEOVIM_ARCH=x86_64 \
        PLASTICINE_NEOVIM_TEST_ASSETS=$fixture_assets PLASTICINE_NEOVIM_TEST_CALLS=$case_home/calls \
        "$@" "$chezmoi_bin" -S "$repo_dir" -D "$case_home" -c "$config" --persistent-state "$case_state" apply --no-tty
}

# Preview is local: no metadata, download, or editor execution.
preview_home=$test_root/preview-home
mkdir -p "$preview_home"; : > "$preview_home/calls"
PATH=$fixture_bin:/usr/bin:/bin PLASTICINE_NEOVIM_OS=Linux PLASTICINE_NEOVIM_ARCH=x86_64 \
    PLASTICINE_NEOVIM_TEST_ASSETS=$fixture_assets PLASTICINE_NEOVIM_TEST_CALLS=$preview_home/calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$preview_home" -c "$config" --persistent-state "$test_root/preview-state" diff --no-pager >/dev/null
[ ! -s "$preview_home/calls" ]

# Fresh apply publishes the complete distribution and link before configuration/plugin work.
fresh=$test_root/fresh-home
mkdir -p "$fresh"; : > "$fresh/calls"
apply_case "$fresh" "$test_root/fresh-state" env >/dev/null
[ -L "$fresh/.local/bin/nvim" ]
[ "$(readlink "$fresh/.local/bin/nvim")" = ../opt/neovim/bin/nvim ]
[ -f "$fresh/.local/opt/neovim/share/nvim/runtime/filetype.lua" ]
[ "$(find "$fresh/.config/nvim" -type f | wc -l | tr -d ' ')" -eq 9 ]
grep -Fq 'Lazy! sync' "$fresh/calls"
grep -Fq 'NvimTreeToggle' "$fresh/calls"
printf owner > "$fresh/.config/nvim/lua/local.lua"
distribution_before=$(find -L "$fresh/.local/opt/neovim" -type f -exec shasum -a 256 {} + | sort | shasum -a 256 | awk '{print $1}')
: > "$fresh/calls"
apply_case "$fresh" "$test_root/fresh-state" env >/dev/null
distribution_after=$(find -L "$fresh/.local/opt/neovim" -type f -exec shasum -a 256 {} + | sort | shasum -a 256 | awk '{print $1}')
[ "$distribution_before" = "$distribution_after" ]
[ "$(grep -c '^curl$' "$fresh/calls")" -eq 1 ]
[ -f "$fresh/.config/nvim/lua/local.lua" ]

# A later stable target upgrades the authorized complete distribution in place.
: > "$fresh/calls"
apply_case "$fresh" "$test_root/fresh-state" env PLASTICINE_NEOVIM_TEST_VERSION=0.12.5 >/dev/null
[ "$("$fresh/.local/bin/nvim" --version)" = 'NVIM v0.12.5' ]
[ -f "$fresh/.local/opt/neovim/share/nvim/runtime/filetype.lua" ]
[ -f "$fresh/.config/nvim/lua/local.lua" ]

# Preparation failures preserve an existing direct installation and precede configuration.
for scenario in metadata digest symlink hardlink malformed extraction candidate-health; do
    failed=$test_root/$scenario-home
    cp -R "$fresh" "$failed"; rm -rf "$failed/.config"; : > "$failed/calls"
    case $scenario in
        metadata) flag=PLASTICINE_NEOVIM_BAD_METADATA=1 ;;
        digest) flag=PLASTICINE_NEOVIM_BAD_DIGEST=1 ;;
        symlink|hardlink|malformed) flag=PLASTICINE_NEOVIM_ARCHIVE_FIXTURE=$scenario ;;
        extraction) flag=PLASTICINE_NEOVIM_FAIL_EXTRACT=1 ;;
        candidate-health) flag=PLASTICINE_NEOVIM_FAIL_HEADLESS=1 ;;
    esac
    if apply_case "$failed" "$test_root/$scenario-state" env PLASTICINE_NEOVIM_TEST_VERSION=0.12.4 "$flag" >/dev/null 2>&1; then
        printf 'preparation failure unexpectedly succeeded: %s\n' "$scenario" >&2; exit 1
    fi
    [ "$("$failed/.local/bin/nvim" --version)" = 'NVIM v0.12.5' ]
    [ ! -e "$failed/.config/nvim/init.lua" ]
done

# Outdated external owners are refused without a shadow installation.
external=$test_root/external-home; external_bin=$test_root/external-bin
mkdir -p "$external" "$external_bin"; : > "$external/calls"
sed 's/NVIM v0.12.4/NVIM v0.11.0/' "$test_root/build-0.12.4/nvim-linux-x86_64/bin/nvim" > "$external_bin/nvim"; chmod 755 "$external_bin/nvim"
if PATH=$external_bin:$fixture_bin:/usr/bin:/bin PLASTICINE_NEOVIM_OS=Linux PLASTICINE_NEOVIM_ARCH=x86_64 PLASTICINE_NEOVIM_TEST_ASSETS=$fixture_assets PLASTICINE_NEOVIM_TEST_CALLS=$external/calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$external" -c "$config" --persistent-state "$test_root/external-state" apply --no-tty >/dev/null 2>&1; then
    printf '%s\n' 'outdated external owner unexpectedly succeeded.' >&2; exit 1
fi
[ ! -e "$external/.local/opt/neovim" ] && [ ! -e "$external/.config/nvim/init.lua" ]

# Destination appearance during download aborts no-clobber publication.
race=$test_root/race-home; mkdir -p "$race"; : > "$race/calls"
if apply_case "$race" "$test_root/race-state" env PLASTICINE_NEOVIM_RACE_TARGET="$race/.local/opt/neovim" >/dev/null 2>&1; then
    printf '%s\n' 'destination race unexpectedly succeeded.' >&2; exit 1
fi
[ ! -e "$race/.local/bin/nvim" ] && [ ! -e "$race/.config/nvim/init.lua" ]

# A failed authorized upgrade switch preserves the active complete distribution.
publication=$test_root/publication-home
mkdir -p "$publication"; : > "$publication/calls"
apply_case "$publication" "$test_root/publication-state" env PLASTICINE_NEOVIM_TEST_VERSION=0.12.4 >/dev/null
rm -rf "$publication/.config"; : > "$publication/calls"
before_publication=$("$publication/.local/bin/nvim" --version)
if apply_case "$publication" "$test_root/publication-state" env \
    PLASTICINE_NEOVIM_TEST_VERSION=0.12.5 PLASTICINE_NEOVIM_FAIL_PUBLICATION=1 >/dev/null 2>&1; then
    printf '%s\n' 'publication failure unexpectedly succeeded.' >&2; exit 1
fi
[ "$("$publication/.local/bin/nvim" --version)" = "$before_publication" ]
[ ! -e "$publication/.config/nvim/init.lua" ]

# Local conflicts and unsupported environments/platforms stop before mutation.
conflict=$test_root/conflict-home; mkdir -p "$conflict/.config/nvim"; printf 'set number\n' > "$conflict/.config/nvim/init.vim"
if apply_case "$conflict" "$test_root/conflict-state" env >/dev/null 2>&1; then exit 1; fi
unsupported=$test_root/unsupported-home; mkdir -p "$unsupported"; : > "$unsupported/calls"
if PATH=$fixture_bin:/usr/bin:/bin PLASTICINE_NEOVIM_OS=Windows PLASTICINE_NEOVIM_ARCH=x86_64 PLASTICINE_NEOVIM_TEST_ASSETS=$fixture_assets PLASTICINE_NEOVIM_TEST_CALLS=$unsupported/calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$unsupported" -c "$config" --persistent-state "$test_root/unsupported-state" apply --no-tty >/dev/null 2>&1; then exit 1; fi
[ ! -s "$unsupported/calls" ]

# Plugin failure occurs after distribution/config publication and a retry converges.
plugin=$test_root/plugin-home; mkdir -p "$plugin"; : > "$plugin/calls"
if apply_case "$plugin" "$test_root/plugin-state" env PLASTICINE_NEOVIM_FAIL_HEADLESS=1 >/dev/null 2>&1; then
    printf '%s\n' 'plugin failure unexpectedly succeeded.' >&2; exit 1
fi
[ -x "$plugin/.local/bin/nvim" ] && [ -f "$plugin/.config/nvim/init.lua" ]
apply_case "$plugin" "$test_root/plugin-state" env >/dev/null

"$repo_dir/install.sh" --help > "$test_root/help"
grep -Fq -- '--neovim' "$test_root/help"
printf '%s\n' 'neovim archive and entrypoint tests passed'
