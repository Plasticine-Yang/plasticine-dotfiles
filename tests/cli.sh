#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-cli-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'cli: %s\n' "$1" >&2; exit 1; }

assert_file() {
    [ -f "$1" ] || fail "missing file: $1"
}

assert_status() {
    expected_status=$1
    shift
    set +e
    "$@" >"$test_root/stdout" 2>"$test_root/stderr"
    actual_status=$?
    set -e
    [ "$actual_status" -eq "$expected_status" ] ||
        fail "expected exit $expected_status, got $actual_status from $*"
}

assert_output() {
    output_file=$1
    expected_file=$2
    cmp -s "$output_file" "$expected_file" || {
        diff -u "$expected_file" "$output_file" >&2 || true
        fail "unexpected output in $output_file"
    }
}

make_installer() {
    version=$1
    status=$2
    destination=$3
    sed -e "s/@VERSION@/$version/g" -e "s/@STATUS@/$status/g" \
        "$test_root/installer.fixture" >"$destination"
    chmod 755 "$destination"
}

make_updater() {
    status=$1
    destination=$2
    sed "s/@STATUS@/$status/g" "$test_root/updater.fixture" >"$destination"
    chmod 755 "$destination"
}

cat >"$test_root/installer.fixture" <<'EOF'
#!/bin/sh
readonly_repo_revision='0123456789abcdef0123456789abcdef01234567'
readonly_release_version='@VERSION@'
readonly_source_sha256='123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0'
readonly_plugins_sha256='abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789'
printf '%s\n' "installer @VERSION@"
printf '%s\n' "installer @VERSION@ stderr" >&2
: >"$PLASTICINE_TEST_ARGV"
for argument in "$@"; do
    printf '<%s>\n' "$argument" >>"$PLASTICINE_TEST_ARGV"
done
exit @STATUS@
EOF
cat >"$test_root/updater.fixture" <<'EOF'
#!/bin/sh
printf '%s\n' 'updater invoked'
printf '<%s>\n' "$#" >"$PLASTICINE_TEST_UPDATER_ARGV"
exit @STATUS@
EOF

installer_v1=$test_root/install-v1.sh
installer_v2=$test_root/install-v2.sh
updater_v1=$test_root/update-v1
updater_v2=$test_root/update-v2
make_installer v1.2.3 23 "$installer_v1"
make_installer v2.0.0 27 "$installer_v2"
make_updater 31 "$updater_v1"
make_updater 32 "$updater_v2"

# Package construction rejects the mutable metadata in a source checkout.
development_installer=$test_root/development-install.sh
sed \
    -e "s/readonly_repo_revision='[^']*'/readonly_repo_revision=''/" \
    -e "s/readonly_release_version='[^']*'/readonly_release_version=''/" \
    "$installer_v1" >"$development_installer"
chmod 755 "$development_installer"
assert_status 1 "$repo_dir/cli/build-version-package.sh" v1.2.3 \
    "$development_installer" "$updater_v1" "$test_root/development-package"
[ ! -e "$test_root/development-package" ] || fail 'development package was constructed'

# Release metadata and the package identity must agree exactly.
assert_status 1 "$repo_dir/cli/build-version-package.sh" v9.9.9 \
    "$installer_v1" "$updater_v1" "$test_root/mismatched-package"
[ ! -e "$test_root/mismatched-package" ] || fail 'mismatched package was constructed'

incomplete_installer=$test_root/incomplete-install.sh
sed "s/readonly_source_sha256='[^']*'/readonly_source_sha256=''/" \
    "$installer_v1" >"$incomplete_installer"
chmod 755 "$incomplete_installer"
assert_status 1 "$repo_dir/cli/build-version-package.sh" v1.2.3 \
    "$incomplete_installer" "$updater_v1" "$test_root/incomplete-package"
[ ! -e "$test_root/incomplete-package" ] || fail 'incomplete package was constructed'

prefix=$test_root/prefix
release_root=$prefix/share/plasticine/releases
mkdir -p "$prefix/bin" "$release_root"
cp "$repo_dir/cli/plasticine" "$prefix/bin/plasticine"
chmod 755 "$prefix/bin/plasticine"

"$repo_dir/cli/build-version-package.sh" v1.2.3 "$installer_v1" "$updater_v1" \
    "$release_root/v1.2.3"
"$repo_dir/cli/build-version-package.sh" v2.0.0 "$installer_v2" "$updater_v2" \
    "$release_root/v2.0.0"
ln -s releases/v1.2.3 "$prefix/share/plasticine/current"

cli=$prefix/bin/plasticine
argv_file=$test_root/installer-argv
updater_argv_file=$test_root/updater-argv
export PLASTICINE_TEST_ARGV="$argv_file" PLASTICINE_TEST_UPDATER_ARGV="$updater_argv_file"

# Local informational commands do not delegate to the installer or updater.
printf '%s\n' 'plasticine v1.2.3' >"$test_root/expected"
assert_status 0 "$cli" --version
assert_output "$test_root/stdout" "$test_root/expected"
[ ! -s "$test_root/stderr" ] || fail '--version wrote stderr'
[ ! -e "$argv_file" ] || fail '--version invoked the installer'

cat >"$test_root/expected" <<'EOF'
Usage: plasticine [installer options]
       plasticine self-update
       plasticine --help
       plasticine --version

Without arguments, Plasticine opens interactive tool selection. Installer
options such as -y and tool flags are passed unchanged to the local release.
EOF
assert_status 0 "$cli" --help
assert_output "$test_root/stdout" "$test_root/expected"
[ ! -s "$test_root/stderr" ] || fail '--help wrote stderr'

# No arguments preserve interactive delegation and the installer's status.
printf '%s\n' 'installer v1.2.3' >"$test_root/expected"
assert_status 23 "$cli"
assert_output "$test_root/stdout" "$test_root/expected"
printf '%s\n' 'installer v1.2.3 stderr' >"$test_root/expected"
assert_output "$test_root/stderr" "$test_root/expected"
[ ! -s "$argv_file" ] || fail 'no-argument invocation gained arguments'

# Every installer argument remains a distinct, byte-for-byte shell argument.
path_with_spaces="$test_root/a_key/owner key"
assert_status 23 "$cli" -y --github-ssh --github-ssh-key "$path_with_spaces" --fnm
printf '%s\n' 'installer v1.2.3' >"$test_root/expected"
assert_output "$test_root/stdout" "$test_root/expected"
printf '%s\n' 'installer v1.2.3 stderr' >"$test_root/expected"
assert_output "$test_root/stderr" "$test_root/expected"
cat >"$test_root/expected" <<EOF
<-y>
<--github-ssh>
<--github-ssh-key>
<$path_with_spaces>
<--fnm>
EOF
assert_output "$argv_file" "$test_root/expected"

# self-update is an exclusive command and crosses an executable package seam.
printf '%s\n' 'updater invoked' >"$test_root/expected"
assert_status 31 "$cli" self-update
assert_output "$test_root/stdout" "$test_root/expected"
printf '%s\n' '<0>' >"$test_root/expected"
assert_output "$updater_argv_file" "$test_root/expected"

assert_status 2 "$cli" self-update --fnm
[ ! -s "$test_root/stdout" ] || fail 'invalid self-update usage wrote stdout'
cat >"$test_root/expected" <<'EOF'
plasticine: self-update does not accept installer options.
Usage: plasticine [installer options]
       plasticine self-update
       plasticine --help
       plasticine --version

Without arguments, Plasticine opens interactive tool selection. Installer
options such as -y and tool flags are passed unchanged to the local release.
EOF
assert_output "$test_root/stderr" "$test_root/expected"

assert_status 2 "$cli" -y self-update
assert_output "$test_root/stderr" "$test_root/expected"

# Switching only current selects another immutable package for later calls.
rm "$prefix/share/plasticine/current"
ln -s releases/v2.0.0 "$prefix/share/plasticine/current"
printf '%s\n' 'plasticine v2.0.0' >"$test_root/expected"
assert_status 0 "$cli" --version
assert_output "$test_root/stdout" "$test_root/expected"
assert_status 27 "$cli" -y --neovim
printf '%s\n' 'installer v2.0.0' >"$test_root/expected"
assert_output "$test_root/stdout" "$test_root/expected"
printf '%s\n' 'installer v2.0.0 stderr' >"$test_root/expected"
assert_output "$test_root/stderr" "$test_root/expected"
printf '%s\n' '<-y>' '<--neovim>' >"$test_root/expected"
assert_output "$argv_file" "$test_root/expected"

# A broken current pointer fails closed; it never searches a checkout/latest.
rm "$prefix/share/plasticine/current"
ln -s releases/missing "$prefix/share/plasticine/current"
assert_status 1 "$cli" --version
[ ! -s "$test_root/stdout" ] || fail 'broken current pointer wrote stdout'
printf '%s\n' 'plasticine: current version package is unavailable.' >"$test_root/expected"
assert_output "$test_root/stderr" "$test_root/expected"

printf '%s\n' 'CLI tests passed'
