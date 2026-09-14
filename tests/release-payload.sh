#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-release-payload-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'release payload: %s\n' "$1" >&2; exit 1; }

[ -f "$repo_dir/lib/release-payload.sh" ] || fail 'release payload module is missing'
[ -f "$repo_dir/lib/managed-plugins.sh" ] || fail 'managed plugin restore module is missing'

# shellcheck disable=SC1091
. "$repo_dir/lib/release-payload.sh"
# shellcheck disable=SC1091
. "$repo_dir/lib/managed-plugins.sh"

source_repo=$test_root/source-repo
mkdir -p "$source_repo"
git -C "$source_repo" init -q
git -C "$source_repo" symbolic-ref HEAD refs/heads/main
printf '%s\n' payload > "$source_repo/content"
git -C "$source_repo" add content
git -C "$source_repo" -c user.name=test -c user.email=test@example.com commit -qm payload
revision=$(git -C "$source_repo" rev-parse HEAD)
git -C "$source_repo" branch release "$revision"
git -C "$source_repo" bundle create "$test_root/source.bundle" release

plugin_repo=$test_root/plugin-repo
mkdir -p "$plugin_repo"
git -C "$plugin_repo" init -q
git -C "$plugin_repo" symbolic-ref HEAD refs/heads/main
printf '%s\n' plugin > "$plugin_repo/plugin.lua"
git -C "$plugin_repo" add plugin.lua
git -C "$plugin_repo" -c user.name=test -c user.email=test@example.com commit -qm plugin
plugin_revision=$(git -C "$plugin_repo" rev-parse HEAD)
git -C "$plugin_repo" remote add origin https://github.com/example/plugin.git

payload_root=$test_root/payload/managed-plugins
mkdir -p "$payload_root/.local/share/nvim/lazy"
cp -R "$plugin_repo" "$payload_root/.local/share/nvim/lazy/plugin.nvim"
printf 'neovim\t.local/share/nvim/lazy/plugin.nvim\thttps://github.com/example/plugin.git\t%s\n' \
    "$plugin_revision" > "$payload_root/manifest.tsv"
tar -czf "$test_root/plugins.tar.gz" -C "$test_root/payload" managed-plugins

source_digest=$(shasum -a 256 "$test_root/source.bundle" | awk '{print $1}')
plugins_digest=$(shasum -a 256 "$test_root/plugins.tar.gz" | awk '{print $1}')
real_git=$(command -v git)
asset_bin=$test_root/bin
mkdir -p "$asset_bin"
cat > "$asset_bin/curl" <<'EOF'
#!/bin/sh
output=
for argument in "$@"; do
    [ "${previous:-}" != -o ] || output=$argument
    previous=$argument
done
[ -n "$output" ] || exit 91
case $* in
    *plasticine-source.bundle*) cp "$PLASTICINE_TEST_SOURCE_ASSET" "$output" ;;
    *plasticine-managed-plugins.tar.gz*) cp "$PLASTICINE_TEST_PLUGIN_ASSET" "$output" ;;
    *) exit 92 ;;
esac
EOF
cat > "$asset_bin/git" <<'EOF'
#!/bin/sh
case ${1:-}:" $* " in
    clone:*' https://'*|fetch:*' https://'*|pull:*' https://'*|ls-remote:*' https://'*)
        printf '%s\n' "fatal: could not read Username for 'https://github.com': terminal prompts disabled" >&2
        exit 128
        ;;
esac
exec "$PLASTICINE_TEST_REAL_GIT" "$@"
EOF
chmod +x "$asset_bin/curl" "$asset_bin/git"

home=$test_root/home
mkdir -p "$home"
(
    cd "$home"
    PATH=$asset_bin:$PATH \
    PLASTICINE_TEST_REAL_GIT=$real_git \
    PLASTICINE_TEST_SOURCE_ASSET=$test_root/source.bundle \
    PLASTICINE_TEST_PLUGIN_ASSET=$test_root/plugins.tar.gz \
        plasticine_release_acquire_source "$home" https://release.invalid v0.0.0 \
            "$source_digest" "$revision" https://github.com/example/source.git "$home/source"
)
[ "$(git -C "$home/source" rev-parse HEAD)" = "$revision" ]
[ "$(git -C "$home/source" remote get-url origin)" = https://github.com/example/source.git ]

PATH=$asset_bin:$PATH \
PLASTICINE_TEST_REAL_GIT=$real_git \
PLASTICINE_TEST_SOURCE_ASSET=$test_root/source.bundle \
PLASTICINE_TEST_PLUGIN_ASSET=$test_root/plugins.tar.gz \
    plasticine_release_acquire_plugins "$home" https://release.invalid v0.0.0 "$plugins_digest"
plasticine_release_plugins_path=${plasticine_release_plugins_path:-}
[ -n "$plasticine_release_plugins_path" ]
archive=$plasticine_release_plugins_path
plasticine_managed_plugins_restore "$archive" "$home" neovim
[ "$(git -C "$home/.local/share/nvim/lazy/plugin.nvim" rev-parse HEAD)" = "$plugin_revision" ]
[ "$(git -C "$home/.local/share/nvim/lazy/plugin.nvim" remote get-url origin)" = https://github.com/example/plugin.git ]
snapshot_checkout=$home/.local/share/nvim/lazy/plugin.nvim
snapshot_marker=$snapshot_checkout/.git/plasticine-release-snapshot
[ "$(sed -n '1p' "$snapshot_marker")" = "$plugin_revision" ]

# A marked checkout is advanced only while it still exactly matches the prior
# released snapshot. Local changes are never discarded by a later release.
printf '%s\n' owner-change > "$snapshot_checkout/owner-file"
plasticine_managed_plugins_restore "$archive" "$home" neovim
grep -Fqx owner-change "$snapshot_checkout/owner-file"
rm "$snapshot_checkout/owner-file"
plasticine_managed_plugins_restore "$archive" "$home" neovim

# Removing the marker transfers ownership back to the native plugin manager.
# Even a different clean revision with the same official origin is preserved.
rm "$snapshot_marker"
printf '%s\n' owner > "$plugin_repo/owner.lua"
git -C "$plugin_repo" add owner.lua
git -C "$plugin_repo" -c user.name=test -c user.email=test@example.com commit -qm owner
owner_revision=$(git -C "$plugin_repo" rev-parse HEAD)
git -C "$snapshot_checkout" fetch -q "$plugin_repo" "$owner_revision"
git -C "$snapshot_checkout" checkout -q --detach FETCH_HEAD
plasticine_managed_plugins_restore "$archive" "$home" neovim
[ "$(git -C "$snapshot_checkout" rev-parse HEAD)" = "$owner_revision" ]
[ ! -e "$snapshot_marker" ]

# Manifest paths cannot use broad wildcard matches to introduce extra path
# components beneath the managed plugin roots.
unsafe_root=$test_root/unsafe/managed-plugins
mkdir -p "$unsafe_root"
cp -R "$plugin_repo" "$unsafe_root/escape"
printf 'neovim\t.local/share/nvim/lazy/owner/escape\thttps://github.com/example/plugin.git\t%s\n' \
    "$owner_revision" > "$unsafe_root/manifest.tsv"
tar -czf "$test_root/unsafe-plugins.tar.gz" -C "$test_root/unsafe" managed-plugins
if plasticine_managed_plugins_restore "$test_root/unsafe-plugins.tar.gz" "$home" neovim >/dev/null 2>&1; then
    fail 'unsafe nested managed plugin path was accepted'
fi

printf '%s\n' 'release payload tests passed'
