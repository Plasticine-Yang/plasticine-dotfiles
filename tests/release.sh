#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-release-pipeline-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

# Debian 12's mawk treats interval expressions such as {64} literally. Run
# the public release gate with that behavior so checksum validation remains
# portable across every supported CI environment.
portable_awk_bin=$test_root/portable-awk-bin
mkdir "$portable_awk_bin"
real_awk=$(command -v awk)
cat >"$portable_awk_bin/awk" <<'EOF'
#!/bin/sh
for argument do
    case $argument in
        *"{64}"*) exit 97 ;;
    esac
done
exec "$PLASTICINE_TEST_REAL_AWK" "$@"
EOF
chmod 755 "$portable_awk_bin/awk"

work_repo=$test_root/work
mkdir -p "$work_repo"
find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git ! -name dist -exec cp -R {} "$work_repo/" \;
git -C "$work_repo" init -q
git -C "$work_repo" symbolic-ref HEAD refs/heads/main
git -C "$work_repo" add -A
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm release-test
revision=$(git -C "$work_repo" rev-parse HEAD)
origin_repo=$test_root/origin.git
git clone -q --bare "$work_repo" "$origin_repo"

asset_dir=$test_root/assets
plugins_fixture=$test_root/plugins-fixture
mkdir -p "$plugins_fixture/managed-plugins"
printf '%s\n' fixture > "$plugins_fixture/managed-plugins/manifest.tsv"
tar -czf "$test_root/plugins.tar.gz" -C "$plugins_fixture" managed-plugins
(
    cd "$test_root"
    PATH=$portable_awk_bin:$PATH \
    PLASTICINE_TEST_REAL_AWK=$real_awk \
    PLASTICINE_MANAGED_PLUGINS_ASSET=$test_root/plugins.tar.gz \
    CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
        "$repo_dir/scripts/release-gate.sh" "$revision" assets v0.0.1 "$work_repo"
)

cat >"$test_root/expected-assets" <<'EOF'
SHA256SUMS
install.sh
plasticine-cli.tar.gz
plasticine-managed-plugins.tar.gz
plasticine-source.bundle
EOF
find "$asset_dir" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; |
    LC_ALL=C sort >"$test_root/actual-assets"
cmp -s "$test_root/expected-assets" "$test_root/actual-assets" || {
    diff -u "$test_root/expected-assets" "$test_root/actual-assets" >&2 || true
    printf '%s\n' 'release gate did not build the exact asset contract' >&2
    exit 1
}
[ "$(wc -l <"$asset_dir/SHA256SUMS" | tr -d ' ')" -eq 4 ]
for payload in install.sh plasticine-cli.tar.gz plasticine-managed-plugins.tar.gz \
    plasticine-source.bundle; do
    [ "$(awk -v asset="$payload" '$2 == asset { matches++ } END { print matches + 0 }' \
        "$asset_dir/SHA256SUMS")" -eq 1 ] || {
        printf 'SHA256SUMS does not cover %s exactly once\n' "$payload" >&2
        exit 1
    }
done
mkdir "$test_root/cli-package"
tar -xzf "$asset_dir/plasticine-cli.tar.gz" -C "$test_root/cli-package"
printf '%s\n' VERSION install.sh plasticine self-update | LC_ALL=C sort \
    >"$test_root/expected-package"
find "$test_root/cli-package" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; |
    LC_ALL=C sort >"$test_root/actual-package"
cmp -s "$test_root/expected-package" "$test_root/actual-package" || {
    printf '%s\n' 'CLI archive is not the required flat four-file package' >&2
    exit 1
}
cmp -s "$asset_dir/install.sh" "$test_root/cli-package/install.sh" || {
    printf '%s\n' 'release and packaged installers differ' >&2
    exit 1
}
[ "$(cat "$test_root/cli-package/VERSION")" = v0.0.1 ]
[ -x "$test_root/cli-package/plasticine" ]
[ -x "$test_root/cli-package/install.sh" ]
[ -x "$test_root/cli-package/self-update" ]
[ ! -x "$test_root/cli-package/VERSION" ]

# Exercise the generated installer's inlined bootstrap for both a missing and
# an older managed chezmoi without relying on a live Release download.
release_fixture=$test_root/release-fixture
release_fixture_bin=$test_root/release-fixture-bin
mkdir -p "$release_fixture/payload" "$release_fixture_bin"
real_chezmoi=${CHEZMOI_BIN:-$(command -v chezmoi)}
case $real_chezmoi in
    /*) ;;
    *) real_chezmoi=$(command -v "$real_chezmoi") ;;
esac
cat > "$release_fixture/payload/chezmoi" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then printf '%s\n' 'chezmoi version v2.72.1'; exit 0; fi
exec '@REAL_CHEZMOI@' "$@"
EOF
sed "s|@REAL_CHEZMOI@|$real_chezmoi|" "$release_fixture/payload/chezmoi" > "$release_fixture/payload/chezmoi.rendered"
mv "$release_fixture/payload/chezmoi.rendered" "$release_fixture/payload/chezmoi"
chmod 755 "$release_fixture/payload/chezmoi"
tar -czf "$release_fixture/chezmoi_2.72.1_linux_amd64.tar.gz" -C "$release_fixture/payload" chezmoi
cat > "$release_fixture_bin/curl" <<'EOF'
#!/bin/sh
output=''; url=''
while [ "$#" -gt 0 ]; do
    case $1 in -o) output=$2; shift ;; http*) url=$1 ;; esac
    shift
done
printf '%s\n' "$url" >> "$PLASTICINE_TEST_RELEASE_CALLS"
case $url in
    */v2.72.1/chezmoi_2.72.1_linux_amd64.tar.gz) cp "$PLASTICINE_TEST_RELEASE_FIXTURE/chezmoi_2.72.1_linux_amd64.tar.gz" "$output" ;;
    *) exit 98 ;;
esac
EOF
cat > "$release_fixture_bin/shasum" <<'EOF'
#!/bin/sh
for argument do file=$argument; done
case ${file##*/} in
    chezmoi_2.72.1_linux_amd64.tar.gz) printf '%s  %s\n' 9f97d32caca166e5c92160ec3a9325519809c38963121cef38173142065c981f "$file" ;;
    *) exec /usr/bin/shasum "$@" ;;
esac
EOF
cat > "$release_fixture_bin/sha256sum" <<'EOF'
#!/bin/sh
for argument do file=$argument; done
case ${file##*/} in
    chezmoi_2.72.1_linux_amd64.tar.gz) printf '%s  %s\n' 9f97d32caca166e5c92160ec3a9325519809c38963121cef38173142065c981f "$file" ;;
    *)
        if [ -x /usr/bin/sha256sum ]; then exec /usr/bin/sha256sum "$@"; fi
        exec /usr/bin/shasum -a 256 "$file"
        ;;
esac
EOF
chmod +x "$release_fixture_bin"/*
generated=$test_root/generated-bootstrap
mkdir -p "$generated/home"
run_generated_bootstrap() {
    HOME=$generated/home PATH=$release_fixture_bin:/usr/bin:/bin \
    PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$generated/calls \
    PLASTICINE_CHEZMOI_OS=Linux PLASTICINE_CHEZMOI_ARCH=x86_64 PLASTICINE_CHEZMOI_LIBC=glibc \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$generated/source \
    PLASTICINE_RELEASE_ASSET_DIR=$asset_dir \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$generated/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$generated/config/chezmoistate.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$generated/home "$asset_dir/install.sh" -y >/dev/null
}
: > "$generated/calls"
run_generated_bootstrap
[ "$("$generated/home/.local/bin/chezmoi" --version)" = 'chezmoi version v2.72.1' ]
grep -Fxq 'https://github.com/twpayne/chezmoi/releases/download/v2.72.1/chezmoi_2.72.1_linux_amd64.tar.gz' "$generated/calls"
sed 's/v2.72.1/v2.72.0/' "$release_fixture/payload/chezmoi" > "$generated/home/.local/bin/chezmoi"
chmod 755 "$generated/home/.local/bin/chezmoi"
old_hash=$(shasum -a 256 "$generated/home/.local/bin/chezmoi" | awk '{print $1}')
: > "$generated/calls"
run_generated_bootstrap
[ "$("$generated/home/.local/bin/chezmoi" --version)" = 'chezmoi version v2.72.1' ]
[ "$old_hash" != "$(shasum -a 256 "$generated/home/.local/bin/chezmoi" | awk '{print $1}')" ]
grep -Fxq 'https://github.com/twpayne/chezmoi/releases/download/v2.72.1/chezmoi_2.72.1_linux_amd64.tar.gz' "$generated/calls"

# Install the first release into a persistent scenario so the next generated
# release can prove that an existing detached source advances explicitly.
upgrade_dir=$test_root/upgrade
mkdir -p "$upgrade_dir/home"
run_release_installer() {
    HOME=$upgrade_dir/home \
    PLASTICINE_CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    PLASTICINE_RELEASE_ASSET_DIR=$1 \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$upgrade_dir/source \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$upgrade_dir/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$upgrade_dir/config/chezmoistate.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$upgrade_dir/home \
        "$1/install.sh" -y >/dev/null
}
run_release_installer "$asset_dir"
[ "$(git -C "$upgrade_dir/source" rev-parse HEAD)" = "$revision" ]
grep -Fq -- '--git-config' "$asset_dir/install.sh"
grep -Fq -- '--neovim' "$asset_dir/install.sh"
grep -Fq -- '--fnm' "$asset_dir/install.sh"
grep -Fq -- '--herdr' "$asset_dir/install.sh"
for module in lazygit fnm herdr neovim shell; do
    test -f "$upgrade_dir/source/lib/$module-bootstrap.sh"
done
grep -Fq 'lazygit_version=0.65.1' "$upgrade_dir/source/lib/lazygit-bootstrap.sh"
grep -Fq '02beacbcda0fa342e50ae3480ba8147307353af3fb28e1d5f790e02329c201a6' "$upgrade_dir/source/lib/lazygit-bootstrap.sh"
grep -Fq 'latest available formula' "$upgrade_dir/source/lib/fnm-bootstrap.sh"
grep -Fq 'stable-release metadata' "$upgrade_dir/source/lib/herdr-bootstrap.sh"
grep -Fq 'neovim_version=0.12.5' "$upgrade_dir/source/lib/neovim-bootstrap.sh"
grep -Fq 'bce0f56eda1f1b1db6eee8f4133d7a38813ea07933837dd1777411ca384c6875' "$upgrade_dir/source/lib/neovim-bootstrap.sh"
grep -Fq 'chezmoi_version=2.72.1' "$asset_dir/install.sh"
grep -Fq '9f97d32caca166e5c92160ec3a9325519809c38963121cef38173142065c981f' "$asset_dir/install.sh"
for production_source in "$asset_dir/install.sh" \
    "$upgrade_dir/source/lib/chezmoi-bootstrap.sh" \
    "$upgrade_dir/source/lib/lazygit-bootstrap.sh" \
    "$upgrade_dir/source/lib/neovim-bootstrap.sh"; do
    if grep -Fq 'api.github.com' "$production_source"; then
        printf 'production source contains a GitHub API dependency: %s\n' "$production_source" >&2
        exit 1
    fi
done
grep -Fq 'antidote update' "$upgrade_dir/source/lib/shell-bootstrap.sh"

# Advancing main after the asset was built must not change what it installs.
printf '%s\n' 'later main content' >> "$work_repo/README.md"
git -C "$work_repo" add README.md
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm later-main
git -C "$work_repo" push -q "$origin_repo" HEAD:main
later_revision=$(git -C "$work_repo" rev-parse HEAD)
[ "$later_revision" != "$revision" ]
CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    "$repo_dir/scripts/verify-release.sh" "$asset_dir" "$revision" v0.0.1
next_asset_dir=$test_root/next-assets
PLASTICINE_MANAGED_PLUGINS_ASSET=$test_root/plugins.tar.gz \
    "$repo_dir/scripts/build-release.sh" "$later_revision" "$next_asset_dir" v0.0.2 "$work_repo"
run_release_installer "$next_asset_dir"
[ "$(git -C "$upgrade_dir/source" rev-parse HEAD)" = "$later_revision" ]
[ "$(git -C "$upgrade_dir/source" symbolic-ref -q HEAD || true)" = '' ]

if "$repo_dir/scripts/build-release.sh" short "$test_root/invalid" v0.0.1 "$work_repo" >/dev/null 2>&1; then
    printf '%s\n' 'release builder accepted a short revision' >&2
    exit 1
fi
if "$repo_dir/scripts/build-release.sh" "$revision" "$asset_dir" v0.0.1 "$work_repo" >/dev/null 2>&1; then
    printf '%s\n' 'release builder overwrote an existing output directory' >&2
    exit 1
fi
if "$repo_dir/scripts/build-release.sh" "$revision" "$test_root/invalid-version" v01.0.1 "$work_repo" >/dev/null 2>&1; then
    printf '%s\n' 'release builder accepted a non-canonical version' >&2
    exit 1
fi

malformed_assets=$test_root/malformed-assets
cp -R "$asset_dir" "$malformed_assets"
mkdir "$test_root/malformed-package"
tar -xzf "$malformed_assets/plasticine-cli.tar.gz" -C "$test_root/malformed-package"
printf '%s\n' unexpected >"$test_root/malformed-package/EXTRA"
tar -czf "$malformed_assets/plasticine-cli.tar.gz" -C "$test_root/malformed-package" \
    plasticine install.sh self-update VERSION EXTRA
(
    cd "$malformed_assets"
    shasum -a 256 install.sh plasticine-cli.tar.gz plasticine-source.bundle \
        plasticine-managed-plugins.tar.gz >SHA256SUMS
)
if CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    "$repo_dir/scripts/verify-release.sh" "$malformed_assets" "$revision" v0.0.1 \
        >/dev/null 2>&1; then
    printf '%s\n' 'release verifier accepted an archive with an extra entry' >&2
    exit 1
fi

printf '%s\n' 'release tests passed'
