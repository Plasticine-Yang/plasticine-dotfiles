#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi)}
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-lazygit-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

fail() { printf 'lazygit tests: %s\n' "$1" >&2; exit 1; }
file_mode() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }

work_repo=$test_root/work
mkdir -p "$work_repo"
find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$work_repo/" \;
git -C "$work_repo" init -q
git -C "$work_repo" add -A
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm lazygit-test
origin_repo=$test_root/origin.git
git clone -q --bare "$work_repo" "$origin_repo"

protect_bin=$test_root/protect-bin
mkdir -p "$protect_bin"
for command_name in zsh brew apt-get sudo chsh dscl getent; do
    cat > "$protect_bin/$command_name" <<EOF
#!/bin/sh
printf '%s\n' '$command_name probed' >> '$test_root/shell-probes'
exit 99
EOF
done
chmod +x "$protect_bin"/*

healthy_bin=$test_root/healthy-bin
mkdir -p "$healthy_bin"
cat > "$healthy_bin/lazygit" <<'EOF'
#!/bin/sh
[ -z "${PLASTICINE_TEST_LAZYGIT_UNHEALTHY:-}" ] || exit 9
[ "${1:-}" = --version ] || exit 99
printf '%s\n' healthy >> "$PLASTICINE_TEST_LAZYGIT_PROBES"
printf '%s\n' 'lazygit version 99.0.0'
EOF
chmod +x "$healthy_bin/lazygit"
base_path=$PATH

release_bin=$test_root/release-bin
release_fixture=$test_root/release-fixture
mkdir -p "$release_bin" "$release_fixture/payload"
cat > "$release_fixture/payload/lazygit" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || exit 99
printf '%s\n' 'lazygit version 1.2.3'
EOF
chmod 755 "$release_fixture/payload/lazygit"
tar -czf "$release_fixture/lazygit_1.2.3_linux_x86_64.tar.gz" -C "$release_fixture/payload" lazygit
cp "$release_fixture/lazygit_1.2.3_linux_x86_64.tar.gz" "$release_fixture/lazygit_1.2.3_linux_arm64.tar.gz"
cp "$release_fixture/lazygit_1.2.3_linux_x86_64.tar.gz" "$release_fixture/lazygit_1.2.3_darwin_x86_64.tar.gz"
cp "$release_fixture/lazygit_1.2.3_linux_x86_64.tar.gz" "$release_fixture/lazygit_1.2.3_darwin_arm64.tar.gz"
: > "$release_fixture/checksums.txt"
for release_asset in "$release_fixture"/*.tar.gz; do
    release_checksum=$(shasum -a 256 "$release_asset" | awk '{print $1}')
    printf '%s  %s\n' "$release_checksum" "${release_asset##*/}" >> "$release_fixture/checksums.txt"
done
cat > "$release_fixture/latest.json" <<'EOF'
{"tag_name":"v1.2.3"}
EOF
cat > "$release_bin/curl" <<'EOF'
#!/bin/sh
output=''
url=''
while [ "$#" -gt 0 ]; do
    case $1 in
        -o) output=$2; shift ;;
        http*) url=$1 ;;
    esac
    shift
done
printf '%s\n' "$url" >> "$PLASTICINE_TEST_RELEASE_CALLS"
case ${PLASTICINE_TEST_CURL_FAIL:-}:$url in
    metadata:*/releases/latest | archive:*/lazygit_*.tar.gz | checksums:*/checksums.txt) exit 97 ;;
esac
case $url in
    */releases/latest) source=$PLASTICINE_TEST_RELEASE_FIXTURE/latest.json ;;
    */checksums.txt) source=$PLASTICINE_TEST_RELEASE_FIXTURE/checksums.txt ;;
    */lazygit_*.tar.gz) source=$PLASTICINE_TEST_RELEASE_FIXTURE/${url##*/} ;;
    *) exit 98 ;;
esac
cp "$source" "$output"
EOF
chmod +x "$release_bin/curl"

run_installer() {
    scenario=$1
    shift
    PATH=$healthy_bin:$protect_bin:$base_path \
    PLASTICINE_TEST_LAZYGIT_PROBES=$test_root/lazygit-probes \
    PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$scenario/config/state.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario/home \
        "$repo_dir/install.sh" "$@"
}

shell_block=$test_root/shell-block
cat > "$shell_block" <<'EOF'
# >>> Plasticine shell >>>
if [ -r "$HOME/.plasticine/zsh/shared.zsh" ]; then
    if ! . "$HOME/.plasticine/zsh/shared.zsh"; then
        if [[ -o interactive ]]; then
            print -ru2 -- "plasticine: shared shell configuration unavailable"
        fi
    fi
fi
# <<< Plasticine shell <<<
EOF
lazygit_block=$test_root/lazygit-block
cat > "$lazygit_block" <<'EOF'
# >>> Plasticine lazygit >>>
alias lg='lazygit'
# <<< Plasticine lazygit <<<
EOF

# Tool options require -y. Missing Lazygit follows the verified official release route; unhealthy state is never replaced.
missing_y=$test_root/missing-y; mkdir -p "$missing_y/home"
if run_installer "$missing_y" --lazygit </dev/null >/dev/null 2>&1; then fail '--lazygit without -y succeeded'; fi
test ! -e "$missing_y/data"
missing=$test_root/missing; mkdir -p "$missing/home"
: > "$missing/release-calls"
if ! PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$missing/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$missing/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$missing/config/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$missing/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=amd64 \
    PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$missing/release-calls \
    "$repo_dir/install.sh" -y --lazygit >"$missing/out" 2>"$missing/err"; then
    cat "$missing/err" >&2; fail 'missing Lazygit release installation failed'
fi
test -x "$missing/home/.local/bin/lazygit" || fail 'release binary was not published'
test "$(file_mode "$missing/home/.local/bin/lazygit")" = 755 || fail 'release binary mode is not 0755'
cmp -s "$lazygit_block" "$missing/home/.zshrc" || fail 'alias was not applied after release health'
grep -Fq '/releases/latest' "$missing/release-calls" || fail 'latest metadata was not resolved during apply'
grep -Fq 'checksums.txt' "$missing/release-calls" || fail 'checksums were not downloaded'
before_release_hash=$(shasum -a 256 "$missing/home/.local/bin/lazygit" | awk '{print $1}')
: > "$missing/release-calls"
PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$missing/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$missing/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$missing/config/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$missing/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=amd64 \
    PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$missing/release-calls \
    "$repo_dir/install.sh" -y --lazygit >/dev/null
test ! -s "$missing/release-calls" || fail 'healthy release rerun used the network'
test "$before_release_hash" = "$(shasum -a 256 "$missing/home/.local/bin/lazygit" | awk '{print $1}')" || fail 'healthy release binary changed'

# Planning maps every reviewed OS/architecture spelling without network or writes.
for platform in Darwin:x86_64:darwin:x86_64 Darwin:arm64:darwin:arm64 Linux:amd64:linux:x86_64 Linux:aarch64:linux:arm64; do
    old_ifs=$IFS; IFS=:; set -- $platform; IFS=$old_ifs
    fixture_os=$1; fixture_arch=$2; expected_os=$3; expected_arch=$4
    plan_home=$test_root/plan-$fixture_os-$fixture_arch; mkdir -p "$plan_home"
    : > "$test_root/plan-curl"
    (
        # Deliberately scoped to this fixture subshell.
        # shellcheck disable=SC2030
        PATH=$release_bin:$protect_bin:/usr/bin:/bin
        PLASTICINE_LAZYGIT_OS=$fixture_os; PLASTICINE_LAZYGIT_ARCH=$fixture_arch
        PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture; PLASTICINE_TEST_RELEASE_CALLS=$test_root/plan-curl
        export PATH PLASTICINE_LAZYGIT_OS PLASTICINE_LAZYGIT_ARCH PLASTICINE_TEST_RELEASE_FIXTURE PLASTICINE_TEST_RELEASE_CALLS
        # shellcheck disable=SC1091
        . "$repo_dir/lib/lazygit-bootstrap.sh"
        plasticine_lazygit_plan "$plan_home"
        # Assigned by plasticine_lazygit_plan from the sourced module.
        # shellcheck disable=SC2154
        test "$lazygit_asset_os:$lazygit_asset_arch" = "$expected_os:$expected_arch"
        plasticine_lazygit_preview > "$plan_home/preview"
    ) || fail "platform mapping failed for $fixture_os/$fixture_arch"
    test ! -s "$test_root/plan-curl" || fail 'planning used the network'
    test ! -e "$plan_home/.local" || fail 'planning wrote destination state'
    grep -Fq 'package manager: none; privilege: none; credentials: none; terminal prompt: none' "$plan_home/preview" || fail 'preview omitted effect statement'
done
for unsupported in FreeBSD:x86_64 Linux:riscv64; do
    old_ifs=$IFS; IFS=:; set -- $unsupported; IFS=$old_ifs
    fixture_os=$1; fixture_arch=$2
    unsupported_home=$test_root/unsupported-$fixture_os-$fixture_arch; mkdir -p "$unsupported_home"
    # shellcheck disable=SC1091
    if (PLASTICINE_LAZYGIT_OS=$fixture_os PLASTICINE_LAZYGIT_ARCH=$fixture_arch; export PLASTICINE_LAZYGIT_OS PLASTICINE_LAZYGIT_ARCH; . "$repo_dir/lib/lazygit-bootstrap.sh"; plasticine_lazygit_plan "$unsupported_home") >/dev/null 2>&1; then
        fail "unsupported $unsupported succeeded"
    fi
    test ! -e "$unsupported_home/.local" || fail 'unsupported target caused effects'
done

# The complete release path uses the exact reviewed asset on every supported
# OS/architecture spelling, verifies it, extracts only `lazygit`, and publishes
# it with executable mode. These fixtures never reach the network.
for platform in Darwin:x86_64:darwin:x86_64 Darwin:arm64:darwin:arm64 Linux:amd64:linux:x86_64 Linux:aarch64:linux:arm64; do
    old_ifs=$IFS; IFS=:; set -- $platform; IFS=$old_ifs
    fixture_os=$1; fixture_arch=$2; expected_os=$3; expected_arch=$4
    route_matrix=$test_root/route-matrix-$fixture_os-$fixture_arch
    mkdir -p "$route_matrix/home"; : > "$route_matrix/calls"
    (
        # Deliberately scoped to this fixture subshell.
        # shellcheck disable=SC2030
        PATH=$release_bin:$protect_bin:/usr/bin:/bin
        PLASTICINE_LAZYGIT_OS=$fixture_os; PLASTICINE_LAZYGIT_ARCH=$fixture_arch
        PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture; PLASTICINE_TEST_RELEASE_CALLS=$route_matrix/calls
        export PATH PLASTICINE_LAZYGIT_OS PLASTICINE_LAZYGIT_ARCH PLASTICINE_TEST_RELEASE_FIXTURE PLASTICINE_TEST_RELEASE_CALLS
        # shellcheck disable=SC1091
        . "$repo_dir/lib/lazygit-bootstrap.sh"
        plasticine_lazygit_plan "$route_matrix/home"
        plasticine_lazygit_prepare
    ) || fail "release path failed for $fixture_os/$fixture_arch"
    expected_asset=lazygit_1.2.3_${expected_os}_${expected_arch}.tar.gz
    grep -Fxq "https://github.com/jesseduffield/lazygit/releases/download/v1.2.3/$expected_asset" "$route_matrix/calls" ||
        fail "wrong release asset requested for $fixture_os/$fixture_arch"
    test -x "$route_matrix/home/.local/bin/lazygit" || fail "release was not published for $fixture_os/$fixture_arch"
    cmp -s "$release_fixture/payload/lazygit" "$route_matrix/home/.local/bin/lazygit" ||
        fail "published member was not the exact lazygit payload for $fixture_os/$fixture_arch"
    test "$(file_mode "$route_matrix/home/.local/bin/lazygit")" = 755 || fail "published mode was not 0755 for $fixture_os/$fixture_arch"
done

# Invalid checksum evidence never publishes a binary or applies the alias.
for checksum_case in missing duplicate malformed mismatch; do
    checksum_fixture=$test_root/checksum-$checksum_case-fixture
    checksum_scenario=$test_root/checksum-$checksum_case
    cp -R "$release_fixture" "$checksum_fixture"; mkdir -p "$checksum_scenario/home"
    asset=lazygit_1.2.3_linux_x86_64.tar.gz
    valid_line=$(grep "  $asset$" "$release_fixture/checksums.txt")
    grep -v "  $asset$" "$release_fixture/checksums.txt" > "$checksum_fixture/checksums.txt"
    case $checksum_case in
        missing) ;;
        duplicate) printf '%s\n%s\n' "$valid_line" "$valid_line" >> "$checksum_fixture/checksums.txt" ;;
        malformed) printf '%s  %s\n' abc "$asset" >> "$checksum_fixture/checksums.txt" ;;
        mismatch) printf '%064d  %s\n' 0 "$asset" >> "$checksum_fixture/checksums.txt" ;;
    esac
    : > "$checksum_scenario/calls"
    if PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
        PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$checksum_scenario/data/chezmoi \
        PLASTICINE_CHEZMOI_CONFIG_FILE=$checksum_scenario/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$checksum_scenario/config/state \
        PLASTICINE_CHEZMOI_DEST_DIR=$checksum_scenario/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64 \
        PLASTICINE_TEST_RELEASE_FIXTURE=$checksum_fixture PLASTICINE_TEST_RELEASE_CALLS=$checksum_scenario/calls \
        "$repo_dir/install.sh" -y --lazygit >/dev/null 2>"$checksum_scenario/err"; then
        fail "$checksum_case checksum succeeded"
    fi
    test ! -e "$checksum_scenario/home/.local/bin/lazygit" || fail "$checksum_case published a binary"
    test ! -e "$checksum_scenario/home/.zshrc" || fail "$checksum_case applied configuration"
done

# Metadata/download/extraction failures stay before publication and configuration.
for route_case in metadata archive checksums invalid-tag extraction; do
    route_fixture=$test_root/route-$route_case-fixture
    route_scenario=$test_root/route-$route_case
    cp -R "$release_fixture" "$route_fixture"; mkdir -p "$route_scenario/home"
    curl_fail=$route_case
    case $route_case in
        invalid-tag) printf '%s\n' '{"tag_name":"latest"}' > "$route_fixture/latest.json"; curl_fail='' ;;
        extraction) printf '%s\n' corrupt > "$route_fixture/lazygit_1.2.3_linux_x86_64.tar.gz"; curl_fail=''
            checksum=$(shasum -a 256 "$route_fixture/lazygit_1.2.3_linux_x86_64.tar.gz" | awk '{print $1}')
            grep -v '  lazygit_1.2.3_linux_x86_64.tar.gz$' "$route_fixture/checksums.txt" > "$route_fixture/checksums.new"
            printf '%s  %s\n' "$checksum" lazygit_1.2.3_linux_x86_64.tar.gz >> "$route_fixture/checksums.new"
            mv "$route_fixture/checksums.new" "$route_fixture/checksums.txt" ;;
    esac
    : > "$route_scenario/calls"
    if PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
        PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$route_scenario/data/chezmoi \
        PLASTICINE_CHEZMOI_CONFIG_FILE=$route_scenario/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$route_scenario/config/state \
        PLASTICINE_CHEZMOI_DEST_DIR=$route_scenario/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64 \
        PLASTICINE_TEST_RELEASE_FIXTURE=$route_fixture PLASTICINE_TEST_RELEASE_CALLS=$route_scenario/calls PLASTICINE_TEST_CURL_FAIL=$curl_fail \
        "$repo_dir/install.sh" -y --lazygit >/dev/null 2>"$route_scenario/err"; then
        fail "$route_case failure gate succeeded"
    fi
    test ! -e "$route_scenario/home/.local/bin/lazygit" || fail "$route_case published a binary"
    test ! -e "$route_scenario/home/.zshrc" || fail "$route_case applied configuration"
done

# Non-regular destination components are rejected during read-only planning.
for unsafe_destination in local-symlink bin-file target-symlink target-directory; do
    unsafe_release=$test_root/release-unsafe-$unsafe_destination; mkdir -p "$unsafe_release/home"
    case $unsafe_destination in
        local-symlink) ln -s "$unsafe_release/elsewhere" "$unsafe_release/home/.local" ;;
        bin-file) mkdir "$unsafe_release/home/.local"; : > "$unsafe_release/home/.local/bin" ;;
        target-symlink) mkdir -p "$unsafe_release/home/.local/bin"; ln -s "$unsafe_release/elsewhere" "$unsafe_release/home/.local/bin/lazygit" ;;
        target-directory) mkdir -p "$unsafe_release/home/.local/bin/lazygit" ;;
    esac
    # shellcheck disable=SC1091
    if (PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64; export PLASTICINE_LAZYGIT_OS PLASTICINE_LAZYGIT_ARCH; . "$repo_dir/lib/lazygit-bootstrap.sh"; plasticine_lazygit_plan "$unsafe_release/home") >/dev/null 2>&1; then
        fail "unsafe destination $unsafe_destination succeeded"
    fi
done
unhealthy=$test_root/unhealthy; mkdir -p "$unhealthy/home"
if PLASTICINE_TEST_LAZYGIT_UNHEALTHY=1 run_installer "$unhealthy" -y --lazygit >/dev/null 2>"$unhealthy/err"; then fail 'unhealthy Lazygit succeeded'; fi
unset PLASTICINE_TEST_LAZYGIT_UNHEALTHY
grep -Fq 'left untouched' "$unhealthy/err"
test ! -e "$unhealthy/home/.zshrc"

# Lazygit-only preserves arbitrary bytes and unmanaged native/legacy state, never
# probes shell state, and restores mode.
single=$test_root/single; mkdir -p "$single/home"
printf 'owner\015\012\303\251\000\377tail' > "$single/home/.zshrc"
mkdir -p "$single/home/.config/lazygit" "$single/home/.cache/lazygit" \
    "$single/home/project/.git" "$single/home/.plasticine-dotfiles/runtime"
printf 'native config\n' > "$single/home/.config/lazygit/config.yml"
printf 'cache and log\n' > "$single/home/.cache/lazygit/lazygit.log"
printf 'repository state\n' > "$single/home/project/.git/lazygit-state"
printf 'legacy state\n' > "$single/home/.plasticine-dotfiles/runtime/lazygit"
unmanaged_before=$(find "$single/home/.config/lazygit" "$single/home/.cache/lazygit" \
    "$single/home/project" "$single/home/.plasticine-dotfiles" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
cp "$single/home/.zshrc" "$single/before"; chmod 640 "$single/home/.zshrc"
run_installer "$single" -y --lazygit >/dev/null
cat "$lazygit_block" > "$single/expected"; cat "$single/before" >> "$single/expected"
cmp -s "$single/expected" "$single/home/.zshrc" || fail 'outside bytes changed'
test "$(file_mode "$single/home/.zshrc")" = 640 || fail 'mode not restored'
test ! -e "$test_root/shell-probes" || fail 'lazygit-only probed shell state'
backup=$(find "$single/home/.plasticine/backups/integration-blocks" -name '.zshrc.plasticine-backup-*')
cmp -s "$single/before" "$backup" || fail 'backup differs from original'
test "$(file_mode "$backup")" = 600 || fail 'backup mode is not 0600'
test "$(file_mode "$single/home/.plasticine/backups")" = 700 || fail 'backup parent mode is not 0700'
before_hash=$(find "$single/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
run_installer "$single" -y --lazygit >/dev/null
after_hash=$(find "$single/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
test "$before_hash" = "$after_hash" || fail 'satisfied rerun changed files'
test "$(find "$single/home/.plasticine/backups/integration-blocks" -name '.zshrc.plasticine-backup-*' | wc -l | tr -d ' ')" = 1 || fail 'rerun created backup'
unmanaged_after=$(find "$single/home/.config/lazygit" "$single/home/.cache/lazygit" \
    "$single/home/project" "$single/home/.plasticine-dotfiles" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
test "$unmanaged_before" = "$unmanaged_after" || fail 'selected apply or satisfied rerun changed unmanaged Lazygit/legacy state'
test ! -e "$single/home/.plasticine/backups/lazygit" || fail 'unmanaged Lazygit state was backed up'

# An unselected apply must not observe even an unhealthy Lazygit executable and
# leaves all native and legacy state byte-identical.
unselected=$test_root/unselected; mkdir -p "$unselected/home/.config/lazygit" "$unselected/home/.cache/lazygit" "$unselected/home/project/.git" "$unselected/home/.plasticine-dotfiles"
printf 'config\n' > "$unselected/home/.config/lazygit/config.yml"
printf 'cache\n' > "$unselected/home/.cache/lazygit/log"
printf 'repo\n' > "$unselected/home/project/.git/state"
printf 'legacy\n' > "$unselected/home/.plasticine-dotfiles/state"
unselected_before=$(find "$unselected/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
rm -f "$test_root/lazygit-probes"
PLASTICINE_TEST_LAZYGIT_UNHEALTHY=1 run_installer "$unselected" -y >/dev/null
unset PLASTICINE_TEST_LAZYGIT_UNHEALTHY
unselected_after=$(find "$unselected/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
test "$unselected_before" = "$unselected_after" || fail 'unselected apply changed Lazygit or legacy state'
test ! -e "$test_root/lazygit-probes" || fail 'unselected apply probed Lazygit'

# Existing blocks stay in place; missing selected blocks prepend in catalog order.
compose=$test_root/compose; mkdir -p "$compose/home"
printf 'prefix\n' > "$compose/home/.zshrc"; cat "$lazygit_block" >> "$compose/home/.zshrc"; printf 'suffix' >> "$compose/home/.zshrc"
run_installer "$compose" -y --lazygit >/dev/null
printf 'prefix\n' > "$compose/expected"; cat "$lazygit_block" >> "$compose/expected"; printf 'suffix' >> "$compose/expected"
cmp -s "$compose/expected" "$compose/home/.zshrc" || fail 'existing block moved'

# Selected malformed markers fail before the Lazygit health probe; malformed unselected markers are opaque.
malformed=$test_root/malformed; mkdir -p "$malformed/home"
printf '# >>> Plasticine lazygit >>\n' > "$malformed/home/.zshrc"; cp "$malformed/home/.zshrc" "$malformed/before"
rm -f "$test_root/lazygit-probes"
if run_installer "$malformed" -y --lazygit >/dev/null 2>&1; then fail 'malformed selected marker succeeded'; fi
cmp -s "$malformed/before" "$malformed/home/.zshrc" || fail 'malformed file changed'
test ! -e "$test_root/lazygit-probes" || fail 'tool probed before marker validation'
opaque=$test_root/opaque; mkdir -p "$opaque/home"
printf '# >>> Plasticine shell >>\nowner\n' > "$opaque/home/.zshrc"
run_installer "$opaque" -y --lazygit >/dev/null
grep -Fq '# >>> Plasticine shell >>' "$opaque/home/.zshrc" || fail 'unselected marker was inspected'

# Unsafe .zshrc kinds are rejected.
for kind in symlink directory fifo; do
    unsafe=$test_root/unsafe-$kind; mkdir -p "$unsafe/home"
    case $kind in symlink) ln -s "$unsafe/missing" "$unsafe/home/.zshrc" ;; directory) mkdir "$unsafe/home/.zshrc" ;; fifo) mkfifo "$unsafe/home/.zshrc" ;; esac
    if run_installer "$unsafe" -y --lazygit >/dev/null 2>&1; then fail "unsafe $kind succeeded"; fi
done

# Internal values are deduplicated/sorted and unknown values fail at init.
selection=$test_root/selection; mkdir -p "$selection/home"
PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='lazygit github-ssh lazygit shell' \
    PLASTICINE_GITHUB_SSH_KEY=/missing "$chezmoi_bin" -S "$repo_dir" -D "$selection/home" \
    --persistent-state "$selection/state" init -C "$selection/config" >/dev/null 2>&1 || true
# The missing SSH fixture stops later validation, so test the pure set without it.
PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='lazygit lazygit shell' \
    "$chezmoi_bin" -S "$repo_dir" -D "$selection/home" --persistent-state "$selection/state2" init -C "$selection/config2" >/dev/null
grep -Fq 'tools = ["lazygit","shell"]' "$selection/config2" || fail 'selection was not sorted/deduplicated'
if PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='lazygit unknown' \
    "$chezmoi_bin" -S "$repo_dir" -D "$selection/home" --persistent-state "$selection/state3" init -C "$selection/config3" >/dev/null 2>&1; then fail 'unknown selection succeeded'; fi

printf '%s\n' 'lazygit tests passed'
