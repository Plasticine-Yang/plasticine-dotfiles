#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
real_chezmoi=${CHEZMOI_BIN:-$(command -v chezmoi 2>/dev/null || true)}
[ -n "$real_chezmoi" ] || { printf '%s\n' 'chezmoi tests require CHEZMOI_BIN or chezmoi on PATH.' >&2; exit 1; }
case $real_chezmoi in
    /*) ;;
    */*) real_chezmoi=$(cd -- "$(dirname -- "$real_chezmoi")" && pwd -P)/${real_chezmoi##*/} ;;
    *) real_chezmoi=$(command -v "$real_chezmoi" 2>/dev/null || true) ;;
esac
[ -n "$real_chezmoi" ] && [ -x "$real_chezmoi" ] || { printf '%s\n' 'chezmoi tests require CHEZMOI_BIN or chezmoi on PATH.' >&2; exit 1; }
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-chezmoi-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
fail() { printf 'chezmoi tests: %s\n' "$1" >&2; exit 1; }

work=$test_root/work; mkdir -p "$work"
find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$work/" \;
git -C "$work" init -q; git -C "$work" add -A
git -C "$work" -c user.name=test -c user.email=test@example.com commit -qm chezmoi-test
origin=$test_root/origin.git; git clone -q --bare "$work" "$origin"

fixture=$test_root/fixture; fixture_bin=$test_root/fixture-bin
mkdir -p "$fixture" "$fixture_bin"
make_release() {
    version=$1; payload=$fixture/payload-$version; mkdir -p "$payload"
    sed "s|@VERSION@|$version|g; s|@REAL@|$real_chezmoi|g" > "$payload/chezmoi" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then printf '%s\n' 'chezmoi version v@VERSION@'; exit 0; fi
exec '@REAL@' "$@"
EOF
    chmod 755 "$payload/chezmoi"
    for platform in linux_amd64 linux-musl_amd64 linux_arm64 darwin_amd64 darwin_arm64; do
        asset=chezmoi_${version}_${platform}.tar.gz
        tar -czf "$fixture/$asset" -C "$payload" chezmoi
        sum=$(shasum -a 256 "$fixture/$asset" | awk '{print $1}')
        printf '%s  %s\n' "$sum" "$asset" >> "$fixture/chezmoi_${version}_checksums.txt"
    done
}
make_release 2.72.1; make_release 2.73.0
cat > "$fixture_bin/curl" <<'EOF'
#!/bin/sh
output=''; url=''
while [ "$#" -gt 0 ]; do
    case $1 in -o) output=$2; shift ;; http*) url=$1 ;; esac
    shift
done
printf '%s\n' "$url" >> "$PLASTICINE_TEST_CHEZMOI_CALLS"
case ${PLASTICINE_TEST_CHEZMOI_FAIL:-}:$url in download:*/releases/download/*) exit 97 ;; esac
case $url in
    */releases/download/*) cp "$PLASTICINE_TEST_CHEZMOI_FIXTURE/${url##*/}" "$output" ;;
    *) exit 98 ;;
esac
EOF
cat > "$fixture_bin/shasum" <<'EOF'
#!/bin/sh
for argument do file=$argument; done
case ${file##*/} in
    chezmoi_2.72.1_linux_amd64.tar.gz) printf '%s  %s\n' 9f97d32caca166e5c92160ec3a9325519809c38963121cef38173142065c981f "$file" ;;
    chezmoi_2.72.1_linux-musl_amd64.tar.gz) printf '%s  %s\n' b961e2972d6fcd1002f9b986d4a61dc5da288e96aab226434fd5b20a7de80cf9 "$file" ;;
    chezmoi_2.72.1_linux_arm64.tar.gz) printf '%s  %s\n' 75508ef41216b6d64f3145986b751729d7f92d09c6bad77d51cf2895ab35a508 "$file" ;;
    chezmoi_2.72.1_darwin_amd64.tar.gz) printf '%s  %s\n' bf0f0e048291efe126cb8bc51cf566057b92755cd53ce82c45efa11d2f8f4898 "$file" ;;
    chezmoi_2.72.1_darwin_arm64.tar.gz) printf '%s  %s\n' 938d422091cc001e68fe3fd7efea9b923a36facbf2b8db67063639abbaf72de2 "$file" ;;
    *) exec /usr/bin/shasum "$@" ;;
esac
EOF
cat > "$fixture_bin/sha256sum" <<'EOF'
#!/bin/sh
for argument do file=$argument; done
case ${file##*/} in
    chezmoi_2.72.1_linux_amd64.tar.gz) printf '%s  %s\n' 9f97d32caca166e5c92160ec3a9325519809c38963121cef38173142065c981f "$file" ;;
    chezmoi_2.72.1_linux-musl_amd64.tar.gz) printf '%s  %s\n' b961e2972d6fcd1002f9b986d4a61dc5da288e96aab226434fd5b20a7de80cf9 "$file" ;;
    chezmoi_2.72.1_linux_arm64.tar.gz) printf '%s  %s\n' 75508ef41216b6d64f3145986b751729d7f92d09c6bad77d51cf2895ab35a508 "$file" ;;
    chezmoi_2.72.1_darwin_amd64.tar.gz) printf '%s  %s\n' bf0f0e048291efe126cb8bc51cf566057b92755cd53ce82c45efa11d2f8f4898 "$file" ;;
    chezmoi_2.72.1_darwin_arm64.tar.gz) printf '%s  %s\n' 938d422091cc001e68fe3fd7efea9b923a36facbf2b8db67063639abbaf72de2 "$file" ;;
    *)
        if [ -x /usr/bin/sha256sum ]; then exec /usr/bin/sha256sum "$@"; fi
        exec /usr/bin/shasum -a 256 "$file"
        ;;
esac
EOF
cat > "$fixture_bin/mv" <<'EOF'
#!/bin/sh
case ${PLASTICINE_TEST_CHEZMOI_PUBLISH:-} in
    fail) exit 96 ;;
    race) printf '%s\n' 'competing owner' > "$3"; exit 96 ;;
esac
exec /bin/mv "$@"
EOF
chmod +x "$fixture_bin"/*
cat > "$fixture_bin/cp" <<'EOF'
#!/bin/sh
case ${PLASTICINE_TEST_CHEZMOI_PUBLISH:-} in
    race) case $2 in */.chezmoi.plasticine.*) printf '%s\n' 'competing owner' > "$PLASTICINE_TEST_CHEZMOI_TARGET" ;; esac ;;
esac
exec /bin/cp "$@"
EOF
chmod +x "$fixture_bin/cp"
base_path=$PATH

write_tool() {
    path=$1; version=$2; healthy=${3:-yes}; mkdir -p "$(dirname -- "$path")"
    if [ "$healthy" = yes ]; then
        sed "s|@VERSION@|$version|g; s|@REAL@|$real_chezmoi|g" > "$path" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then printf '%s\n' 'chezmoi version v@VERSION@'; exit 0; fi
exec '@REAL@' "$@"
EOF
    else printf '%s\n' '#!/bin/sh' 'exit 9' > "$path"; fi
    chmod 755 "$path"
}

run_direct() {
    scenario=$1; release=$2; shift 2
    HOME=$scenario/home PATH=$fixture_bin:/usr/bin:/bin \
    PLASTICINE_TEST_CHEZMOI_FIXTURE=$fixture PLASTICINE_TEST_CHEZMOI_RELEASE=$release \
    PLASTICINE_TEST_CHEZMOI_CALLS=$scenario/calls \
    PLASTICINE_TEST_CHEZMOI_TARGET=$scenario/home/.local/bin/chezmoi \
    PLASTICINE_TEST_CHEZMOI_PUBLISH=${PLASTICINE_TEST_CHEZMOI_PUBLISH:-} \
    PLASTICINE_CHEZMOI_OS=${PLASTICINE_CHEZMOI_OS:-Linux} PLASTICINE_CHEZMOI_ARCH=${PLASTICINE_CHEZMOI_ARCH:-x86_64} PLASTICINE_CHEZMOI_LIBC=${PLASTICINE_CHEZMOI_LIBC:-glibc} \
    PLASTICINE_DOTFILES_REPO_URL=$origin PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario/source \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$scenario/config/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home "$repo_dir/install.sh" -y "$@"
}

# Missing direct install, current convergence, and a newly published target on the next invocation.
scenario=$test_root/direct; mkdir -p "$scenario/home"; : > "$scenario/calls"
run_direct "$scenario" 2.73.0 > "$scenario/out"
grep -Fq 'observed=missing; target=2.72.1; action=install' "$scenario/out" || fail 'missing action was not reported'
[ "$("$scenario/home/.local/bin/chezmoi" --version)" = 'chezmoi version v2.72.1' ] || fail 'pinned release was not installed'
! grep -Fq 'api.github.com' "$scenario/calls" || fail 'bootstrap queried the GitHub API'
first_hash=$(shasum -a 256 "$scenario/home/.local/bin/chezmoi" | awk '{print $1}')
: > "$scenario/calls"; run_direct "$scenario" 2.73.0 > "$scenario/current-out"
[ ! -s "$scenario/calls" ] || fail 'satisfied check made a release request'
[ "$first_hash" = "$(shasum -a 256 "$scenario/home/.local/bin/chezmoi" | awk '{print $1}')" ] || fail 'current executable was replaced'
grep -Fq 'reusing it without release traffic' "$scenario/current-out" || fail 'reuse was not reported'
: > "$scenario/calls"; run_direct "$scenario" 2.73.0 > "$scenario/update-out"
[ "$("$scenario/home/.local/bin/chezmoi" --version)" = 'chezmoi version v2.72.1' ] || fail 'new upstream release changed the pinned target'
[ ! -s "$scenario/calls" ] || fail 'new upstream release caused network traffic'

# Download failure preserves the working executable and stops before source acquisition.
broken=$test_root/failed-download; mkdir -p "$broken/home/.local/bin"; : > "$broken/calls"
write_tool "$broken/home/.local/bin/chezmoi" 2.72.0
before=$(shasum -a 256 "$broken/home/.local/bin/chezmoi" | awk '{print $1}')
if PLASTICINE_TEST_CHEZMOI_FAIL=download run_direct "$broken" 2.73.0 >/dev/null 2>"$broken/err"; then fail 'download failure succeeded'; fi
[ "$before" = "$(shasum -a 256 "$broken/home/.local/bin/chezmoi" | awk '{print $1}')" ] || fail 'download failure changed working executable'
[ ! -e "$broken/source" ] || fail 'download failure acquired source'
unset PLASTICINE_TEST_CHEZMOI_FAIL

# Every supported platform route selects its exact reviewed pinned asset.
for route in Linux:x86_64:glibc:linux_amd64 Linux:x86_64:musl:linux-musl_amd64 Linux:arm64:glibc:linux_arm64 Darwin:x86_64:glibc:darwin_amd64 Darwin:arm64:glibc:darwin_arm64; do
    old_ifs=$IFS; IFS=:; set -- $route; IFS=$old_ifs
    platform=$test_root/platform-$1-$2-$3; mkdir -p "$platform/home"; : > "$platform/calls"
    PLASTICINE_CHEZMOI_OS=$1 PLASTICINE_CHEZMOI_ARCH=$2 PLASTICINE_CHEZMOI_LIBC=$3 \
        run_direct "$platform" 2.73.0 >/dev/null
    grep -Fq "/v2.72.1/chezmoi_2.72.1_$4.tar.gz" "$platform/calls" || \
        fail "$1/$2/$3 did not select the reviewed pinned asset"
done
# Linux musl arm64 remains unsupported because upstream publishes no reviewed asset.
unsupported_musl=$test_root/unsupported-musl; mkdir -p "$unsupported_musl/home"; : > "$unsupported_musl/calls"
if HOME=$unsupported_musl/home PATH=$fixture_bin:/usr/bin:/bin PLASTICINE_TEST_CHEZMOI_FIXTURE=$fixture \
    PLASTICINE_TEST_CHEZMOI_CALLS=$unsupported_musl/calls PLASTICINE_CHEZMOI_OS=Linux PLASTICINE_CHEZMOI_ARCH=arm64 \
    PLASTICINE_CHEZMOI_LIBC=musl PLASTICINE_DOTFILES_REPO_URL=$origin PLASTICINE_CHEZMOI_SOURCE_DIR=$unsupported_musl/source \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$unsupported_musl/config PLASTICINE_CHEZMOI_STATE_FILE=$unsupported_musl/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$unsupported_musl/home "$repo_dir/install.sh" -y >/dev/null 2>"$unsupported_musl/err"; then
    fail 'unsupported musl arm64 route succeeded'
fi
[ ! -s "$unsupported_musl/calls" ] || fail 'unsupported musl arm64 route made a release request'

# Interrupted replacement leaves the previously observed destination and no stale staged file.
publication=fail
broken=$test_root/publish-$publication; mkdir -p "$broken/home/.local/bin"; : > "$broken/calls"
write_tool "$broken/home/.local/bin/chezmoi" 2.72.0
if PLASTICINE_TEST_CHEZMOI_PUBLISH=$publication run_direct "$broken" 2.73.0 >/dev/null 2>"$broken/err"; then fail "$publication publication succeeded"; fi
[ "$("$broken/home/.local/bin/chezmoi" --version)" = 'chezmoi version v2.72.0' ] || fail 'failed update lost old executable'
[ -z "$(find "$broken/home/.local/bin" -name '.chezmoi.plasticine.*' -print)" ] || fail "$publication left staging"

# External ownership can satisfy current state, but is never mutated or shadowed when outdated.
for state in current outdated unhealthy prerelease; do
    external=$test_root/external-$state; mkdir -p "$external/home" "$external/bin"; : > "$external/calls"
    case $state in current) write_tool "$external/bin/chezmoi" 2.73.0 ;; outdated) write_tool "$external/bin/chezmoi" 2.72.0 ;;
        unhealthy) write_tool "$external/bin/chezmoi" 2.72.2 no ;; prerelease) write_tool "$external/bin/chezmoi" 2.73.0-rc1 ;; esac
    if HOME=$external/home PATH=$external/bin:$fixture_bin:/usr/bin:/bin PLASTICINE_TEST_CHEZMOI_FIXTURE=$fixture PLASTICINE_TEST_CHEZMOI_RELEASE=2.73.0 \
        PLASTICINE_TEST_CHEZMOI_CALLS=$external/calls PLASTICINE_CHEZMOI_OS=Linux PLASTICINE_CHEZMOI_ARCH=x86_64 \
        PLASTICINE_DOTFILES_REPO_URL=$origin PLASTICINE_CHEZMOI_SOURCE_DIR=$external/source \
        PLASTICINE_CHEZMOI_CONFIG_FILE=$external/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$external/config/state \
        PLASTICINE_CHEZMOI_DEST_DIR=$external/home "$repo_dir/install.sh" -y >"$external/out" 2>"$external/err"; then rc=0; else rc=$?; fi
    case $state in current) [ "$rc" -eq 0 ] || fail 'current external owner was rejected' ;;
        *) [ "$rc" -ne 0 ] || fail "$state external owner was accepted"; [ ! -e "$external/home/.local/bin/chezmoi" ] || fail "$state external owner was shadowed" ;; esac
done

# Explicit test/executable overrides retain their interface contract and never query or mutate upstream state.
explicit=$test_root/explicit; mkdir -p "$explicit/home"; : > "$explicit/calls"
HOME=$explicit/home PATH=$fixture_bin:$base_path PLASTICINE_CHEZMOI_BIN=$real_chezmoi PLASTICINE_TEST_CHEZMOI_CALLS=$explicit/calls \
PLASTICINE_DOTFILES_REPO_URL=$origin PLASTICINE_CHEZMOI_SOURCE_DIR=$explicit/source \
PLASTICINE_CHEZMOI_CONFIG_FILE=$explicit/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$explicit/config/state \
PLASTICINE_CHEZMOI_DEST_DIR=$explicit/home "$repo_dir/install.sh" -y >/dev/null
[ ! -s "$explicit/calls" ] || fail 'explicit override queried upstream'
[ ! -e "$explicit/home/.local/bin/chezmoi" ] || fail 'explicit override was shadowed'

printf '%s\n' 'chezmoi tests passed'
