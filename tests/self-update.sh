#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-self-update-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'self-update: %s\n' "$1" >&2; exit 1; }

assert_status() {
    expected=$1
    shift
    set +e
    "$@" >"$test_root/stdout" 2>"$test_root/stderr"
    actual=$?
    set -e
    [ "$actual" -eq "$expected" ] ||
        fail "expected exit $expected, got $actual from $*"
}

make_installer() {
    fixture_version=$1
    fixture_destination=$2
    sed "s/@VERSION@/$fixture_version/g" "$test_root/installer.fixture" >"$fixture_destination"
    chmod 755 "$fixture_destination"
}

make_package() {
    package_version=$1
    package_destination=$2
    package_installer=$test_root/install-$package_version.sh
    make_installer "$package_version" "$package_installer"
    "$repo_dir/cli/build-version-package.sh" "$package_version" "$package_installer" \
        "$repo_dir/cli/version-package/self-update" "$package_destination"
}

make_assets() {
    package_dir=$1
    asset_dir=$2
    mkdir -p "$asset_dir"
    tar -czf "$asset_dir/plasticine-cli.tar.gz" -C "$package_dir" \
        plasticine install.sh self-update VERSION
    (cd "$asset_dir" && shasum -a 256 plasticine-cli.tar.gz >SHA256SUMS)
}

publish_fixture_archive() {
    fixture_package=$1
    fixture_asset_dir=$2
    shift 2
    rm -rf "$fixture_asset_dir"
    mkdir -p "$fixture_asset_dir"
    tar -czf "$fixture_asset_dir/plasticine-cli.tar.gz" -C "$fixture_package" "$@"
    (cd "$fixture_asset_dir" && shasum -a 256 plasticine-cli.tar.gz >SHA256SUMS)
}

cat >"$test_root/installer.fixture" <<'EOF'
#!/bin/sh
readonly_repo_revision='0123456789abcdef0123456789abcdef01234567'
readonly_release_version='@VERSION@'
readonly_source_sha256='123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0'
readonly_plugins_sha256='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'
printf 'installer %s\n' '@VERSION@'
printf '%s\n' '@VERSION@' >>"$PLASTICINE_TEST_INSTALLER_CALLS"
EOF

fixture_bin=$test_root/bin
fixture_releases=$test_root/fixture-releases
mkdir -p "$fixture_bin" "$fixture_releases"
cat >"$fixture_bin/curl" <<'EOF'
#!/bin/sh
set -eu
output=
url=
while [ "$#" -gt 0 ]; do
    case $1 in
        -o) output=$2; shift ;;
        http*) url=$1 ;;
    esac
    shift
done
printf '%s\n' "$url" >>"$PLASTICINE_TEST_CURL_CALLS"
case ${PLASTICINE_TEST_CURL_FAIL:-}:$url in
    discovery:*releases/latest|checksums:*SHA256SUMS|archive:*plasticine-cli.tar.gz) exit 96 ;;
esac
case $url in
    https://api.github.com/repos/Plasticine-Yang/plasticine-dotfiles/releases/latest)
        printf '%s\n' "${PLASTICINE_TEST_LATEST_JSON:-{\"tag_name\":\"v2.0.0\"}}" >"$output"
        ;;
    https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/download/v2.0.0/SHA256SUMS)
        cp "$PLASTICINE_TEST_RELEASES/v2.0.0/SHA256SUMS" "$output"
        ;;
    https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/download/v2.0.0/plasticine-cli.tar.gz)
        cp "$PLASTICINE_TEST_RELEASES/v2.0.0/plasticine-cli.tar.gz" "$output"
        ;;
    *) exit 97 ;;
esac
EOF
chmod 755 "$fixture_bin/curl"

prefix=$test_root/prefix
release_root=$prefix/share/plasticine/releases
mkdir -p "$prefix/bin" "$release_root"
cp "$repo_dir/cli/plasticine" "$prefix/bin/plasticine"
chmod 755 "$prefix/bin/plasticine"
make_package v1.0.0 "$release_root/v1.0.0"
make_package v2.0.0 "$test_root/package-v2.0.0"
make_assets "$test_root/package-v2.0.0" "$fixture_releases/v2.0.0"
ln -s releases/v1.0.0 "$prefix/share/plasticine/current"

export PLASTICINE_TEST_RELEASES="$fixture_releases"
export PLASTICINE_TEST_CURL_CALLS="$test_root/curl-calls"
export PLASTICINE_TEST_INSTALLER_CALLS="$test_root/installer-calls"
PATH=$fixture_bin:$PATH
export PATH
mkdir -p "$test_root/side-effects/source" "$test_root/side-effects/tools"
printf '%s\n' source-before >"$test_root/side-effects/source/state"
printf '%s\n' config-before >"$test_root/side-effects/config"
printf '%s\n' tools-before >"$test_root/side-effects/tools/state"
(cd "$test_root/side-effects" && shasum -a 256 source/state config tools/state) \
    >"$test_root/side-effects-before"

cli=$prefix/bin/plasticine
assert_status 0 "$cli" self-update
grep -Fqx 'plasticine: updated from v1.0.0 to v2.0.0.' "$test_root/stdout" ||
    fail 'successful update was not reported'
[ ! -s "$test_root/stderr" ] || fail 'successful update wrote stderr'
[ "$(readlink "$prefix/share/plasticine/current")" = releases/v2.0.0 ] ||
    fail 'current did not switch atomically to v2.0.0'
[ -d "$release_root/v1.0.0" ] || fail 'old version was not retained'
[ "$("$cli" --version)" = 'plasticine v2.0.0' ] || fail '--version did not use v2'
[ "$("$cli" -y)" = 'installer v2.0.0' ] || fail 'next installer did not use v2'
[ "$(cat "$test_root/installer-calls")" = v2.0.0 ] || fail 'self-update invoked an installer'
(cd "$test_root/side-effects" && shasum -a 256 source/state config tools/state) \
    >"$test_root/side-effects-after"
cmp -s "$test_root/side-effects-before" "$test_root/side-effects-after" ||
    fail 'self-update mutated source, config, or tools sentinels'

cat >"$test_root/expected-curl-calls" <<'EOF'
https://api.github.com/repos/Plasticine-Yang/plasticine-dotfiles/releases/latest
https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/download/v2.0.0/SHA256SUMS
https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/download/v2.0.0/plasticine-cli.tar.gz
EOF
cmp -s "$test_root/expected-curl-calls" "$test_root/curl-calls" ||
    fail 'updater used an unexpected Release discovery/download contract'

# An installed latest package performs discovery only and leaves current intact.
: >"$test_root/curl-calls"
assert_status 0 "$cli" self-update
grep -Fqx 'plasticine: v2.0.0 is already the latest stable version.' "$test_root/stdout" ||
    fail 'same-version no-op was not reported'
[ "$(wc -l <"$test_root/curl-calls" | tr -d ' ')" -eq 1 ] ||
    fail 'same-version no-op downloaded Release assets'
[ "$(readlink "$prefix/share/plasticine/current")" = releases/v2.0.0 ] ||
    fail 'same-version no-op changed current'

select_v1() {
    rm -f "$prefix/share/plasticine/current"
    ln -s releases/v1.0.0 "$prefix/share/plasticine/current"
    rm -rf "$release_root/v2.0.0"
}

assert_v1_working() {
    [ "$(readlink "$prefix/share/plasticine/current")" = releases/v1.0.0 ] ||
        fail "$1 changed current"
    [ "$("$cli" --version)" = 'plasticine v1.0.0' ] || fail "$1 broke --version"
    [ "$("$cli" -y)" = 'installer v1.0.0' ] || fail "$1 broke the installer"
}

# Every external-boundary failure is nonzero and preserves the installed package.
select_v1
for failed_request in discovery checksums archive; do
    export PLASTICINE_TEST_CURL_FAIL=$failed_request
    assert_status 1 "$cli" self-update
    assert_v1_working "$failed_request failure"
done
unset PLASTICINE_TEST_CURL_FAIL

export PLASTICINE_TEST_LATEST_JSON='{"tag_name":"nightly"}'
assert_status 1 "$cli" self-update
assert_v1_working 'invalid discovery metadata'
unset PLASTICINE_TEST_LATEST_JSON

bad_checksum_releases=$test_root/bad-checksum-releases
mkdir -p "$bad_checksum_releases/v2.0.0"
cp "$fixture_releases/v2.0.0/plasticine-cli.tar.gz" \
    "$bad_checksum_releases/v2.0.0/plasticine-cli.tar.gz"
printf '%064d  plasticine-cli.tar.gz\n' 0 >"$bad_checksum_releases/v2.0.0/SHA256SUMS"
PLASTICINE_TEST_RELEASES=$bad_checksum_releases
export PLASTICINE_TEST_RELEASES
assert_status 1 "$cli" self-update
assert_v1_working 'checksum failure'

missing_checksum_releases=$test_root/missing-checksum-releases
mkdir -p "$missing_checksum_releases/v2.0.0"
cp "$fixture_releases/v2.0.0/plasticine-cli.tar.gz" \
    "$missing_checksum_releases/v2.0.0/plasticine-cli.tar.gz"
printf '%064d  another-asset.tar.gz\n' 0 >"$missing_checksum_releases/v2.0.0/SHA256SUMS"
PLASTICINE_TEST_RELEASES=$missing_checksum_releases
export PLASTICINE_TEST_RELEASES
assert_status 1 "$cli" self-update
assert_v1_working 'missing exact checksum entry'

PLASTICINE_TEST_RELEASES=$fixture_releases
export PLASTICINE_TEST_RELEASES

# Archive parsing and candidate validation are real, not curl-fixture behavior.
candidate_case=$test_root/candidate-case
candidate_assets=$test_root/candidate-assets/v2.0.0
run_candidate_failure() {
    case_name=$1
    PLASTICINE_TEST_RELEASES=$test_root/candidate-assets
    export PLASTICINE_TEST_RELEASES
    assert_status 1 "$cli" self-update
    assert_v1_working "$case_name"
}

rm -rf "$candidate_case"
cp -R "$test_root/package-v2.0.0" "$candidate_case"
printf '%s\n' unexpected >"$candidate_case/EXTRA"
publish_fixture_archive "$candidate_case" "$candidate_assets" \
    plasticine install.sh self-update VERSION EXTRA
run_candidate_failure 'extra archive entry'

publish_fixture_archive "$candidate_case" "$candidate_assets" \
    plasticine install.sh self-update
run_candidate_failure 'missing archive entry'

rm -rf "$candidate_case"
cp -R "$test_root/package-v2.0.0" "$candidate_case"
printf '%s\n' v9.9.9 >"$candidate_case/VERSION"
publish_fixture_archive "$candidate_case" "$candidate_assets" \
    plasticine install.sh self-update VERSION
run_candidate_failure 'mismatched package version'

rm -rf "$candidate_case"
cp -R "$test_root/package-v2.0.0" "$candidate_case"
printf '%s\n' v2.0.0 trailing-data >"$candidate_case/VERSION"
publish_fixture_archive "$candidate_case" "$candidate_assets" \
    plasticine install.sh self-update VERSION
run_candidate_failure 'multi-line package version'

rm -rf "$candidate_case"
cp -R "$test_root/package-v2.0.0" "$candidate_case"
chmod 644 "$candidate_case/install.sh"
publish_fixture_archive "$candidate_case" "$candidate_assets" \
    plasticine install.sh self-update VERSION
run_candidate_failure 'non-executable package file'

rm -rf "$candidate_case"
cp -R "$test_root/package-v2.0.0" "$candidate_case"
printf '%s\n' '#!/bin/sh' 'exit 42' >"$candidate_case/plasticine"
chmod 755 "$candidate_case/plasticine"
publish_fixture_archive "$candidate_case" "$candidate_assets" \
    plasticine install.sh self-update VERSION
run_candidate_failure 'candidate health failure'

rm -rf "$candidate_assets"
mkdir -p "$candidate_assets"
printf '%s\n' 'not a gzip archive' >"$candidate_assets/plasticine-cli.tar.gz"
(cd "$candidate_assets" && shasum -a 256 plasticine-cli.tar.gz >SHA256SUMS)
run_candidate_failure 'corrupt archive'

PLASTICINE_TEST_RELEASES=$fixture_releases
export PLASTICINE_TEST_RELEASES

# Publishing never overwrites an existing immutable package.
mkdir "$release_root/v2.0.0"
printf '%s\n' existing >"$release_root/v2.0.0/sentinel"
assert_status 1 "$cli" self-update
assert_v1_working 'publication conflict'
[ "$(cat "$release_root/v2.0.0/sentinel")" = existing ] ||
    fail 'publication conflict overwrote an existing release'
rm -rf "$release_root/v2.0.0"

# mkdir is the portable macOS/Linux concurrency primitive; only one updater owns it.
mkdir "$prefix/share/plasticine/.self-update.lock"
assert_status 1 "$cli" self-update
assert_v1_working 'concurrent update exclusion'
grep -Fqx 'plasticine: self-update: another self-update is already running.' \
    "$test_root/stderr" || fail 'concurrent update did not report exclusion'
rmdir "$prefix/share/plasticine/.self-update.lock"

printf '%s\n' 'self-update tests passed'
