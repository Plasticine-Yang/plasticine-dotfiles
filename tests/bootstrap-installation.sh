#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-bootstrap-installation-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'bootstrap installation: %s\n' "$1" >&2; exit 1; }

release_version=v1.2.3
release_revision=$(git -C "$repo_dir" rev-parse HEAD)
source_digest=123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0
plugins_digest=abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789
release_dir=$test_root/release
mkdir -p "$release_dir"
sed \
    -e "s/readonly_repo_revision=''/readonly_repo_revision='$release_revision'/" \
    -e "s/readonly_release_version=''/readonly_release_version='$release_version'/" \
    -e "s/readonly_source_sha256=''/readonly_source_sha256='$source_digest'/" \
    -e "s/readonly_plugins_sha256=''/readonly_plugins_sha256='$plugins_digest'/" \
    "$repo_dir/install.sh" >"$release_dir/install.rendered"
awk -v chezmoi_module="$repo_dir/lib/chezmoi-bootstrap.sh" \
    -v release_module="$repo_dir/lib/release-payload.sh" '
    /^\[ -f .*lib\/chezmoi-bootstrap\.sh/ {
        while ((getline line < chezmoi_module) > 0) print line
        close(chezmoi_module)
        getline
        getline
        next
    }
    /^\[ -f .*lib\/release-payload\.sh/ {
        while ((getline line < release_module) > 0) print line
        close(release_module)
        getline
        getline
        next
    }
    { print }
' "$release_dir/install.rendered" >"$release_dir/install.sh"
rm "$release_dir/install.rendered"
chmod 755 "$release_dir/install.sh"

cat >"$test_root/self-update" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$test_root/self-update"
package_dir=$test_root/package
"$repo_dir/cli/build-version-package.sh" "$release_version" \
    "$release_dir/install.sh" "$test_root/self-update" "$package_dir"
tar -czf "$release_dir/plasticine-cli.tar.gz" -C "$package_dir" .
package_digest=$(shasum -a 256 "$release_dir/plasticine-cli.tar.gz" | awk '{print $1}')
printf '%s  %s\n' "$package_digest" plasticine-cli.tar.gz >"$release_dir/SHA256SUMS"

run_bootstrap() {
    scenario_home=$1
    shift
    HOME=$scenario_home \
    PLASTICINE_RELEASE_ASSET_DIR=$release_dir \
    PLASTICINE_DOTFILES_REPO_URL=$repo_dir \
    PLASTICINE_CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
        "$release_dir/install.sh" "$@"
}

home=$test_root/home
mkdir -p "$home"
run_bootstrap "$home" -y >"$test_root/install.out"

launcher=$home/.local/bin/plasticine
[ ! -e "$home/cli" ] || fail 'CLI build sources leaked into the managed destination'
[ -x "$launcher" ] || fail 'empty selection did not install an executable launcher'
[ "$("$launcher" --version)" = "plasticine $release_version" ] ||
    fail 'installed launcher did not select the released package'
[ -x "$home/.local/share/plasticine/releases/$release_version/install.sh" ] ||
    fail 'released installer is missing from the immutable version package'
[ "$(readlink "$home/.local/share/plasticine/current")" = "releases/$release_version" ] ||
    fail 'current does not select the installed release'
cmp -s "$launcher" "$repo_dir/cli/plasticine" ||
    fail 'installed launcher is not the stable launcher contract'
grep -Fq "Installed command: $launcher" "$test_root/install.out" ||
    fail 'PATH-missing output did not provide the executable absolute path'
grep -Fq "Add it to PATH for future shells: export PATH=\"$home/.local/bin:\$PATH\"" \
    "$test_root/install.out" || fail 'PATH-missing output did not provide accurate guidance'
[ ! -e "$home/.zshrc" ] && [ ! -e "$home/.profile" ] ||
    fail 'bootstrap edited shell configuration to add PATH'

# Normal local selection runs entirely from the installed immutable package.
mv "$release_dir/plasticine-cli.tar.gz" "$test_root/package-asset"
mv "$release_dir/SHA256SUMS" "$test_root/sums-asset"
HOME=$home \
PLASTICINE_RELEASE_ASSET_DIR=$release_dir \
PLASTICINE_DOTFILES_REPO_URL=$repo_dir \
PLASTICINE_CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    "$launcher" -y >/dev/null
mv "$test_root/package-asset" "$release_dir/plasticine-cli.tar.gz"
mv "$test_root/sums-asset" "$release_dir/SHA256SUMS"

# Installing the same immutable release again is safe and retains command health.
before=$(find "$home/.local/share/plasticine/releases/$release_version" -type f \
    -exec shasum -a 256 {} + | LC_ALL=C sort)
run_bootstrap "$home" -y >/dev/null
after=$(find "$home/.local/share/plasticine/releases/$release_version" -type f \
    -exec shasum -a 256 {} + | LC_ALL=C sort)
[ "$before" = "$after" ] || fail 'same-version bootstrap changed the immutable package'
[ "$("$launcher" --version)" = "plasticine $release_version" ] ||
    fail 'same-version bootstrap broke the installed command'

# Re-running the one-line bootstrap for a newer Release switches current while
# preserving the old immutable four-file package.
next_release_version=v1.2.4
next_release_dir=$test_root/next-release
mkdir "$next_release_dir"
sed "s/readonly_release_version='$release_version'/readonly_release_version='$next_release_version'/" \
    "$release_dir/install.sh" >"$next_release_dir/install.sh"
chmod 755 "$next_release_dir/install.sh"
next_package_dir=$test_root/next-package
"$repo_dir/cli/build-version-package.sh" "$next_release_version" \
    "$next_release_dir/install.sh" "$test_root/self-update" "$next_package_dir"
tar -czf "$next_release_dir/plasticine-cli.tar.gz" -C "$next_package_dir" .
next_package_digest=$(shasum -a 256 "$next_release_dir/plasticine-cli.tar.gz" | awk '{print $1}')
printf '%s  %s\n' "$next_package_digest" plasticine-cli.tar.gz \
    >"$next_release_dir/SHA256SUMS"
upgrade_home=$test_root/upgrade-home
mkdir "$upgrade_home"
run_bootstrap "$upgrade_home" -y >/dev/null
HOME=$upgrade_home \
PLASTICINE_RELEASE_ASSET_DIR=$next_release_dir \
PLASTICINE_DOTFILES_REPO_URL=$repo_dir \
PLASTICINE_CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    "$next_release_dir/install.sh" -y >/dev/null
[ "$(readlink "$upgrade_home/.local/share/plasticine/current")" = \
    "releases/$next_release_version" ] ||
    fail 'newer bootstrap did not switch current to the new release'
[ "$("$upgrade_home/.local/bin/plasticine" --version)" = \
    "plasticine $next_release_version" ] ||
    fail 'newer bootstrap left the old release active'
[ "$(find "$upgrade_home/.local/share/plasticine/releases/$release_version" \
    -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 4 ] ||
    fail 'newer bootstrap contaminated the old immutable package'

# A foreign same-name command is never overwritten.
foreign_home=$test_root/foreign-home
mkdir -p "$foreign_home/.local/bin"
printf '%s\n' '#!/bin/sh' 'printf foreign-command' >"$foreign_home/.local/bin/plasticine"
chmod 755 "$foreign_home/.local/bin/plasticine"
cp "$foreign_home/.local/bin/plasticine" "$test_root/foreign-before"
if run_bootstrap "$foreign_home" -y >"$test_root/foreign.out" 2>"$test_root/foreign.err"; then
    fail 'foreign same-name command was accepted'
fi
cmp -s "$test_root/foreign-before" "$foreign_home/.local/bin/plasticine" ||
    fail 'foreign same-name command was overwritten'
[ ! -e "$foreign_home/.local/share/chezmoi" ] ||
    fail 'foreign command conflict was detected after source work began'

# Symlinked command and install directories fail closed without touching targets.
symlink_home=$test_root/symlink-home
mkdir -p "$symlink_home/.local/bin"
printf '%s\n' symlink-sentinel >"$test_root/symlink-target"
ln -s "$test_root/symlink-target" "$symlink_home/.local/bin/plasticine"
if run_bootstrap "$symlink_home" -y >/dev/null 2>"$test_root/symlink.err"; then
    fail 'symlinked command target was accepted'
fi
[ "$(cat "$test_root/symlink-target")" = symlink-sentinel ] ||
    fail 'symlink command target was overwritten'

unsafe_home=$test_root/unsafe-home
mkdir -p "$unsafe_home" "$test_root/unsafe-local"
ln -s "$test_root/unsafe-local" "$unsafe_home/.local"
if run_bootstrap "$unsafe_home" -y >/dev/null 2>"$test_root/unsafe.err"; then
    fail 'symlinked install directory was accepted'
fi
[ ! -e "$test_root/unsafe-local/bin/plasticine" ] ||
    fail 'symlinked install directory was modified'

unsafe_current_home=$test_root/unsafe-current-home
mkdir -p "$unsafe_current_home/.local/share/plasticine/releases"
printf '%s\n' current-sentinel >"$unsafe_current_home/.local/share/plasticine/current"
if run_bootstrap "$unsafe_current_home" -y >/dev/null 2>"$test_root/unsafe-current.err"; then
    fail 'non-symlink current selector was accepted'
fi
[ "$(cat "$unsafe_current_home/.local/share/plasticine/current")" = current-sentinel ] ||
    fail 'unsafe current selector was overwritten'
[ ! -e "$unsafe_current_home/.local/bin/plasticine" ] ||
    fail 'unsafe current selector left a launcher behind'

# The archive must match the exact SHA256SUMS entry before anything is installed.
checksum_home=$test_root/checksum-home
mkdir -p "$checksum_home"
cp "$release_dir/plasticine-cli.tar.gz" "$test_root/package-good.tar.gz"
printf '%s\n' corrupt >>"$release_dir/plasticine-cli.tar.gz"
if run_bootstrap "$checksum_home" -y >/dev/null 2>"$test_root/checksum.err"; then
    fail 'CLI archive with a mismatched checksum was accepted'
fi
[ ! -e "$checksum_home/.local/bin/plasticine" ] ||
    fail 'checksum failure installed a launcher'
mv "$test_root/package-good.tar.gz" "$release_dir/plasticine-cli.tar.gz"

# A verified archive still cannot write outside its version-package staging root.
traversal_dir=$test_root/traversal
mkdir -p "$traversal_dir/package"
cp -R "$package_dir"/. "$traversal_dir/package/"
printf '%s\n' escaped >"$traversal_dir/escape"
tar -czf "$release_dir/plasticine-cli.tar.gz" -C "$traversal_dir/package" . \
    -C "$traversal_dir/package" ../escape
package_digest=$(shasum -a 256 "$release_dir/plasticine-cli.tar.gz" | awk '{print $1}')
printf '%s  %s\n' "$package_digest" plasticine-cli.tar.gz >"$release_dir/SHA256SUMS"
traversal_home=$test_root/traversal-home
mkdir -p "$traversal_home"
if run_bootstrap "$traversal_home" -y >/dev/null 2>"$test_root/traversal.err"; then
    fail 'CLI archive with a traversal member was accepted'
fi
[ ! -e "$test_root/escape" ] || [ "$(cat "$test_root/escape")" = escaped ] ||
    fail 'CLI archive traversal overwrote a file outside staging'

# Restore the good asset, then ensure an occupied immutable release fails closed.
tar -czf "$release_dir/plasticine-cli.tar.gz" -C "$package_dir" .
package_digest=$(shasum -a 256 "$release_dir/plasticine-cli.tar.gz" | awk '{print $1}')
printf '%s  %s\n' "$package_digest" plasticine-cli.tar.gz >"$release_dir/SHA256SUMS"
printf '%s\n' tampered >>"$home/.local/share/plasticine/releases/$release_version/install.sh"
if run_bootstrap "$home" -y >/dev/null 2>"$test_root/tampered.err"; then
    fail 'tampered immutable package was accepted as the same release'
fi
grep -Fqx tampered "$home/.local/share/plasticine/releases/$release_version/install.sh" ||
    fail 'tampered immutable package was overwritten'

# The source-checkout entrypoint remains usable but cannot invent a release package.
development_home=$test_root/development-home
mkdir -p "$development_home"
HOME=$development_home \
PLASTICINE_DOTFILES_REPO_URL=$repo_dir \
PLASTICINE_CHEZMOI_BIN=${CHEZMOI_BIN:-$(command -v chezmoi)} \
    "$repo_dir/install.sh" -y >/dev/null
[ ! -e "$development_home/.local/bin/plasticine" ] ||
    fail 'development installer created a misleading local CLI'
[ ! -e "$development_home/.local/share/plasticine" ] ||
    fail 'development installer created a misleading version-package root'

# A non-shell Feature selection installs the same independent command.
non_shell_home=$test_root/non-shell-home
mkdir -p "$non_shell_home"
run_bootstrap "$non_shell_home" -y --git-config >/dev/null
[ "$("$non_shell_home/.local/bin/plasticine" --version)" = "plasticine $release_version" ] ||
    fail 'non-shell selection did not install a healthy command'
[ ! -e "$non_shell_home/.zshrc" ] ||
    fail 'non-shell selection unexpectedly installed shell configuration'

if command -v expect >/dev/null 2>&1; then
    cancel_home=$test_root/cancel-home
    mkdir -p "$cancel_home"
    export PLASTICINE_TEST_BOOTSTRAP="$release_dir/install.sh"
    export PLASTICINE_TEST_RELEASE_ASSETS="$release_dir"
    export PLASTICINE_TEST_REPO="$repo_dir"
    export PLASTICINE_TEST_CHEZMOI="${CHEZMOI_BIN:-$(command -v chezmoi)}"
    export PLASTICINE_TEST_CANCEL_HOME="$cancel_home"
    expect <<'EOF'
set timeout 30
set env(HOME) $env(PLASTICINE_TEST_CANCEL_HOME)
set env(PLASTICINE_RELEASE_ASSET_DIR) $env(PLASTICINE_TEST_RELEASE_ASSETS)
set env(PLASTICINE_DOTFILES_REPO_URL) $env(PLASTICINE_TEST_REPO)
set env(PLASTICINE_CHEZMOI_BIN) $env(PLASTICINE_TEST_CHEZMOI)
spawn $env(PLASTICINE_TEST_BOOTSTRAP)
expect -exact {ctrl+a select all}
send -- "\r"
expect -exact {Apply these changes? [y/N] }
send -- "n\r"
expect -exact {plasticine-dotfiles: Cancelled; no changes were applied.}
expect eof
catch wait result
exit [lindex $result 3]
EOF
    cancel_launcher=$cancel_home/.local/bin/plasticine
    [ -x "$cancel_launcher" ] || fail 'cancellation undid the installed launcher'
    [ "$("$cancel_launcher" --version)" = "plasticine $release_version" ] ||
        fail 'installed command was unhealthy after cancellation'
fi

printf '%s\n' 'bootstrap installation tests passed'
