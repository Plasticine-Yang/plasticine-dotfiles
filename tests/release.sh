#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-release-pipeline-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

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
"$repo_dir/scripts/build-release.sh" "$revision" "$asset_dir"
CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    "$repo_dir/scripts/verify-release.sh" "$asset_dir" "$revision" "$origin_repo"

# Install the first release into a persistent scenario so the next generated
# release can prove that an existing detached source advances explicitly.
upgrade_dir=$test_root/upgrade
mkdir -p "$upgrade_dir/home"
run_release_installer() {
    HOME=$upgrade_dir/home \
    PLASTICINE_CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
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
if grep -Fq 'api.github.com' "$asset_dir/install.sh"; then
    printf '%s\n' 'generated installer contains a GitHub API dependency' >&2
    exit 1
fi
grep -Fq 'antidote update' "$upgrade_dir/source/lib/shell-bootstrap.sh"

# Advancing main after the asset was built must not change what it installs.
printf '%s\n' 'later main content' >> "$work_repo/README.md"
git -C "$work_repo" add README.md
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm later-main
git -C "$work_repo" push -q "$origin_repo" HEAD:main
later_revision=$(git -C "$work_repo" rev-parse HEAD)
[ "$later_revision" != "$revision" ]
CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    "$repo_dir/scripts/verify-release.sh" "$asset_dir" "$revision" "$origin_repo"
next_asset_dir=$test_root/next-assets
"$repo_dir/scripts/build-release.sh" "$later_revision" "$next_asset_dir"
run_release_installer "$next_asset_dir"
[ "$(git -C "$upgrade_dir/source" rev-parse HEAD)" = "$later_revision" ]
[ "$(git -C "$upgrade_dir/source" symbolic-ref -q HEAD || true)" = '' ]

if "$repo_dir/scripts/build-release.sh" short "$test_root/invalid" >/dev/null 2>&1; then
    printf '%s\n' 'release builder accepted a short revision' >&2
    exit 1
fi
if "$repo_dir/scripts/build-release.sh" "$revision" "$asset_dir" >/dev/null 2>&1; then
    printf '%s\n' 'release builder overwrote an existing output directory' >&2
    exit 1
fi

printf '%s\n' 'release tests passed'
