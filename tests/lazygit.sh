#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_command=${CHEZMOI_BIN:-chezmoi}
case $chezmoi_command in
    */*) chezmoi_bin=$chezmoi_command ;;
    *) chezmoi_bin=$(command -v "$chezmoi_command" 2>/dev/null || true) ;;
esac
[ -n "$chezmoi_bin" ] && [ -x "$chezmoi_bin" ] || {
    printf '%s\n' 'lazygit tests require an executable CHEZMOI_BIN or chezmoi on PATH.' >&2
    exit 1
}
case $chezmoi_bin in
    /*) ;;
    *) chezmoi_bin=$(cd -- "$(dirname -- "$chezmoi_bin")" && pwd -P)/${chezmoi_bin##*/} ;;
esac
test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-lazygit-test.XXXXXX")
test_root=$(cd "$test_root" && pwd -P)
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
[ "${PLASTICINE_TEST_PUBLISHED_HEALTH_RACE:-}" != 1 ] ||
    case $0 in */.local/bin/lazygit) rm -f "$0"; printf '%s\n' owner-replacement > "$0"; exit 96 ;; esac
[ "${PLASTICINE_TEST_PUBLISHED_HEALTH_FAIL:-}" != 1 ] ||
    case $0 in */.local/bin/lazygit) exit 96 ;; esac
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
cat > "$release_bin/ln" <<'EOF'
#!/bin/sh
case ${PLASTICINE_TEST_PUBLISH_FAILURE:-} in
    fail) exit 95 ;;
    race) printf '%s\n' competing-owner > "$2"; exit 95 ;;
esac
exec /bin/ln "$@"
EOF
chmod +x "$release_bin/ln"

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
# The catalog is a source invariant, independent of selection: only the exact
# canonical shell/lazygit sequence may reach init, target inspection, or probes.
for catalog_case in missing empty reordered duplicate unknown; do
    catalog_work=$test_root/$catalog_case-work
    git clone -q "$origin_repo" "$catalog_work"
    case $catalog_case in
        missing) rm "$catalog_work/.chezmoitemplates/zsh-integration-catalog" ;;
        empty) : > "$catalog_work/.chezmoitemplates/zsh-integration-catalog" ;;
        reordered) printf '%s\n' lazygit shell > "$catalog_work/.chezmoitemplates/zsh-integration-catalog" ;;
        duplicate) printf '%s\n' shell lazygit lazygit > "$catalog_work/.chezmoitemplates/zsh-integration-catalog" ;;
        unknown) printf '%s\n' shell unknown > "$catalog_work/.chezmoitemplates/zsh-integration-catalog" ;;
    esac
    git -C "$catalog_work" add -A .chezmoitemplates/zsh-integration-catalog
    git -C "$catalog_work" -c user.name=test -c user.email=test@example.com commit -qm "$catalog_case catalog"
    catalog_origin=$test_root/$catalog_case.git
    git clone -q --bare "$catalog_work" "$catalog_origin"
    catalog_scenario=$test_root/catalog-$catalog_case
    mkdir -p "$catalog_scenario/home"
    mkfifo "$catalog_scenario/home/.zshrc"
    rm -f "$test_root/lazygit-probes" "$test_root/shell-probes"
    if PATH=$healthy_bin:$protect_bin:$base_path PLASTICINE_TEST_LAZYGIT_PROBES=$test_root/lazygit-probes \
        PLASTICINE_CHEZMOI_BIN=$chezmoi_bin PLASTICINE_DOTFILES_REPO_URL=$catalog_origin \
        PLASTICINE_CHEZMOI_SOURCE_DIR=$catalog_scenario/data/chezmoi PLASTICINE_CHEZMOI_CONFIG_FILE=$catalog_scenario/config/chezmoi.toml \
        PLASTICINE_CHEZMOI_STATE_FILE=$catalog_scenario/state/chezmoistate.boltdb PLASTICINE_CHEZMOI_DEST_DIR=$catalog_scenario/home \
        "$repo_dir/install.sh" -y >/dev/null 2>"$catalog_scenario/err"; then
        fail "$catalog_case source integration catalog succeeded"
    fi
    case $catalog_case in
        missing) grep -Fq 'does not contain the Zsh integration catalog' "$catalog_scenario/err" || fail 'missing catalog error was not actionable' ;;
        duplicate) grep -Fq 'Duplicate Zsh integration catalog entry: lazygit' "$catalog_scenario/err" || fail 'duplicate catalog error was not actionable' ;;
        unknown) grep -Fq 'Invalid Zsh integration catalog entry: unknown' "$catalog_scenario/err" || fail 'unknown catalog error was not actionable' ;;
        *) grep -Fq 'must contain exactly shell then lazygit' "$catalog_scenario/err" || fail "$catalog_case catalog error was not actionable" ;;
    esac
    test ! -e "$catalog_scenario/config/chezmoi.toml" || fail "$catalog_case catalog created a config file"
    test ! -d "$catalog_scenario/config" || fail "$catalog_case catalog created the config parent"
    test ! -d "$catalog_scenario/state" || fail "$catalog_case catalog created the state parent"
    test -p "$catalog_scenario/home/.zshrc" || fail "$catalog_case catalog inspected or changed the destination .zshrc sentinel"
    test ! -e "$test_root/lazygit-probes" || fail "$catalog_case catalog allowed a Lazygit probe"
    test ! -e "$test_root/shell-probes" || fail "$catalog_case catalog allowed a shell tool probe"
done

# The interactive default path also rejects a catalog missing lazygit before
# chezmoi can render or prompt, with the same zero-effect boundary.
command -v expect >/dev/null 2>&1 || fail 'expect is required for interactive catalog validation'
interactive_catalog_work=$test_root/interactive-catalog-work
git clone -q "$origin_repo" "$interactive_catalog_work"
printf '%s\n' shell > "$interactive_catalog_work/.chezmoitemplates/zsh-integration-catalog"
git -C "$interactive_catalog_work" add .chezmoitemplates/zsh-integration-catalog
git -C "$interactive_catalog_work" -c user.name=test -c user.email=test@example.com commit -qm interactive-missing-lazygit
interactive_catalog_origin=$test_root/interactive-catalog.git
git clone -q --bare "$interactive_catalog_work" "$interactive_catalog_origin"
interactive_catalog=$test_root/interactive-catalog
mkdir -p "$interactive_catalog/home"
mkfifo "$interactive_catalog/home/.zshrc"
rm -f "$test_root/lazygit-probes" "$test_root/shell-probes"
export PLASTICINE_TEST_INTERACTIVE_CATALOG="$interactive_catalog"
export PLASTICINE_TEST_INTERACTIVE_CATALOG_ORIGIN="$interactive_catalog_origin"
export PLASTICINE_TEST_REPO_DIR="$repo_dir" PLASTICINE_TEST_CHEZMOI="$chezmoi_bin"
export PLASTICINE_TEST_PATH="$healthy_bin:$protect_bin:$base_path"
export PLASTICINE_TEST_LAZYGIT_PROBES="$test_root/lazygit-probes"
expect <<'EOF'
set timeout 20
set scenario $env(PLASTICINE_TEST_INTERACTIVE_CATALOG)
set env(PATH) $env(PLASTICINE_TEST_PATH)
set env(PLASTICINE_CHEZMOI_BIN) $env(PLASTICINE_TEST_CHEZMOI)
set env(PLASTICINE_DOTFILES_REPO_URL) $env(PLASTICINE_TEST_INTERACTIVE_CATALOG_ORIGIN)
set env(PLASTICINE_CHEZMOI_SOURCE_DIR) $scenario/data/chezmoi
set env(PLASTICINE_CHEZMOI_CONFIG_FILE) $scenario/config/chezmoi.toml
set env(PLASTICINE_CHEZMOI_STATE_FILE) $scenario/state/chezmoistate.boltdb
set env(PLASTICINE_CHEZMOI_DEST_DIR) $scenario/home
log_file $scenario/output
spawn $env(PLASTICINE_TEST_REPO_DIR)/install.sh
expect eof
set rc [lindex [wait] 3]
if {$rc == 0} { exit 1 }
EOF
grep -Fq 'must contain exactly shell then lazygit' "$interactive_catalog/output" || fail 'interactive incomplete catalog error was not actionable'
! grep -Fq '选择要处理的工具' "$interactive_catalog/output" || fail 'interactive incomplete catalog reached init prompt'
test ! -e "$interactive_catalog/config/chezmoi.toml" || fail 'interactive incomplete catalog created a config file'
test ! -d "$interactive_catalog/config" || fail 'interactive incomplete catalog created the config parent'
test ! -d "$interactive_catalog/state" || fail 'interactive incomplete catalog created the state parent'
test -p "$interactive_catalog/home/.zshrc" || fail 'interactive incomplete catalog inspected or changed .zshrc'
test ! -e "$test_root/lazygit-probes" || fail 'interactive incomplete catalog probed Lazygit'
test ! -e "$test_root/shell-probes" || fail 'interactive incomplete catalog probed a shell tool'
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

# Archive membership is an exact contract: a missing or duplicate top-level
# lazygit member fails before publication or configuration.
for member_case in missing duplicate; do
    member_fixture=$test_root/member-$member_case-fixture
    member_scenario=$test_root/member-$member_case
    cp -R "$release_fixture" "$member_fixture"; mkdir -p "$member_scenario/home" "$member_fixture/member-work"
    asset=lazygit_1.2.3_linux_x86_64.tar.gz
    case $member_case in
        missing) printf '%s\n' decoy > "$member_fixture/member-work/not-lazygit"; tar -czf "$member_fixture/$asset" -C "$member_fixture/member-work" not-lazygit ;;
        duplicate)
            mkdir -p "$member_fixture/member-work/one" "$member_fixture/member-work/two"
            cp "$release_fixture/payload/lazygit" "$member_fixture/member-work/one/lazygit"
            cp "$release_fixture/payload/lazygit" "$member_fixture/member-work/two/lazygit"
            tar -czf "$member_fixture/$asset" -C "$member_fixture/member-work/one" lazygit -C "$member_fixture/member-work/two" lazygit
            ;;
    esac
    checksum=$(shasum -a 256 "$member_fixture/$asset" | awk '{print $1}')
    grep -v "  $asset$" "$member_fixture/checksums.txt" > "$member_fixture/checksums.new"
    printf '%s  %s\n' "$checksum" "$asset" >> "$member_fixture/checksums.new"
    mv "$member_fixture/checksums.new" "$member_fixture/checksums.txt"
    : > "$member_scenario/calls"
    if PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
        PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$member_scenario/data/chezmoi \
        PLASTICINE_CHEZMOI_CONFIG_FILE=$member_scenario/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$member_scenario/config/state \
        PLASTICINE_CHEZMOI_DEST_DIR=$member_scenario/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64 \
        PLASTICINE_TEST_RELEASE_FIXTURE=$member_fixture PLASTICINE_TEST_RELEASE_CALLS=$member_scenario/calls \
        "$repo_dir/install.sh" -y --lazygit >/dev/null 2>"$member_scenario/err"; then
        fail "$member_case archive member succeeded"
    fi
    grep -Fq 'exactly one member named lazygit' "$member_scenario/err" || fail "$member_case archive error was not actionable"
    test ! -e "$member_scenario/home/.local/bin/lazygit" || fail "$member_case archive published a binary"
    test ! -e "$member_scenario/home/.zshrc" || fail "$member_case archive applied configuration"
done

# Publication failures, a competing target appearing at publication time, and
# a post-publication health failure all leave configuration unapplied.
for publish_case in failure race post-health; do
    publish_scenario=$test_root/publish-$publish_case
    mkdir -p "$publish_scenario/home"; : > "$publish_scenario/calls"
    publish_failure=
    post_health_failure=
    post_health_race=
    case $publish_case in
        failure) publish_failure=fail ;;
        race) publish_failure=race ;;
        post-health) post_health_failure=1 ;;
    esac
    if PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
        PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$publish_scenario/data/chezmoi \
        PLASTICINE_CHEZMOI_CONFIG_FILE=$publish_scenario/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$publish_scenario/config/state \
        PLASTICINE_CHEZMOI_DEST_DIR=$publish_scenario/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64 \
        PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$publish_scenario/calls \
        PLASTICINE_TEST_PUBLISH_FAILURE=$publish_failure PLASTICINE_TEST_PUBLISHED_HEALTH_FAIL=$post_health_failure \
        PLASTICINE_TEST_PUBLISHED_HEALTH_RACE=$post_health_race \
        "$repo_dir/install.sh" -y --lazygit >/dev/null 2>"$publish_scenario/err"; then
        fail "$publish_case succeeded"
    fi
    test ! -e "$publish_scenario/home/.zshrc" || fail "$publish_case applied configuration"
    case $publish_case in
        race) test "$(cat "$publish_scenario/home/.local/bin/lazygit")" = competing-owner || fail 'publication race clobbered competing target' ;;
        post-health)
            test -f "$publish_scenario/home/.local/bin/lazygit" || fail 'post-health failure removed the published target'
            retained_target=$(cd "$publish_scenario/home/.local/bin" && pwd -P)/lazygit
            grep -Fq "retained at $retained_target" "$publish_scenario/err" || fail 'post-health failure did not name the retained target'
            grep -Fq 'remove it if it is the failed publication, before rerunning' "$publish_scenario/err" || fail 'post-health failure did not explain how to make rerun safe'
            ;;
        *) test ! -e "$publish_scenario/home/.local/bin/lazygit" || fail "$publish_case left a published binary" ;;
    esac
    test -z "$(find "$publish_scenario/home/.local/bin" -name '.lazygit.plasticine.*' -print 2>/dev/null)" || fail "$publish_case left publication staging"
done

# Follow the documented recovery for an ordinary failed publication: remove
# the retained unhealthy file, then rerun the same controlled release route.
post_health_retry=$test_root/publish-post-health
rm "$post_health_retry/home/.local/bin/lazygit"
if ! PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$post_health_retry/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$post_health_retry/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$post_health_retry/config/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$post_health_retry/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64 \
    PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$post_health_retry/calls \
    "$repo_dir/install.sh" -y --lazygit >/dev/null 2>"$post_health_retry/retry-err"; then
    cat "$post_health_retry/retry-err" >&2
    fail 'post-health retry after removing retained target failed'
fi
test "$(wc -l < "$post_health_retry/calls" | tr -d ' ')" -eq 6 || fail 'post-health retry did not perform exactly two release downloads'
"$post_health_retry/home/.local/bin/lazygit" --version >/dev/null 2>&1 || fail 'post-health retry did not leave a healthy executable'
cmp -s "$lazygit_block" "$post_health_retry/home/.zshrc" || fail 'post-health retry did not apply the Lazygit alias'
test -z "$(find "$post_health_retry/home/.local/bin" -name '.lazygit.plasticine.*' -print)" || fail 'post-health retry left publication staging'

# A replacement racing the post-publication health check is Owner state. It is
# retained on both supported operating-system routes while apply still fails.
for race_platform in Linux:x86_64 Darwin:arm64; do
    old_ifs=$IFS; IFS=:; set -- $race_platform; IFS=$old_ifs
    race_os=$1; race_arch=$2
    publish_scenario=$test_root/post-health-race-$race_os
    mkdir -p "$publish_scenario/home"; : > "$publish_scenario/calls"
    if PATH=$release_bin:$protect_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
        PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$publish_scenario/data/chezmoi \
        PLASTICINE_CHEZMOI_CONFIG_FILE=$publish_scenario/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$publish_scenario/config/state \
        PLASTICINE_CHEZMOI_DEST_DIR=$publish_scenario/home PLASTICINE_LAZYGIT_OS=$race_os PLASTICINE_LAZYGIT_ARCH=$race_arch \
        PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$publish_scenario/calls \
        PLASTICINE_TEST_PUBLISHED_HEALTH_RACE=1 "$repo_dir/install.sh" -y --lazygit >/dev/null 2>"$publish_scenario/err"; then
        fail "post-health Owner replacement race succeeded on $race_os"
    fi
    test "$(cat "$publish_scenario/home/.local/bin/lazygit")" = owner-replacement || fail "post-health cleanup removed an Owner target on $race_os"
    grep -Fq 'repair the Owner file' "$publish_scenario/err" || fail "post-health race did not direct Owner repair on $race_os"
    test ! -e "$publish_scenario/home/.zshrc" || fail "post-health race applied configuration on $race_os"
    test -z "$(find "$publish_scenario/home/.local/bin" -name '.lazygit.plasticine.*' -print)" || fail "post-health race left publication staging on $race_os"
done

# When Lazygit succeeds before a later selected tool fails, its healthy binary
# remains. A rerun resumes from that observation without another download.
partial=$test_root/partial-rerun
partial_bin=$partial/bin
mkdir -p "$partial/home/.antidote" "$partial_bin"; : > "$partial/calls"; : > "$partial/bundle-fails"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$partial/os-release"
real_zsh=$(command -v zsh)
cat > "$partial_bin/getent" <<EOF
#!/bin/sh
printf 'owner:x:%s:%s:Owner:%s:%s\n' "$(id -u)" "$(id -u)" '$partial/home' '$real_zsh'
EOF
cat > "$partial_bin/chsh" <<'EOF'
#!/bin/sh
exit 99
EOF
cat > "$partial/home/.antidote/antidote.zsh" <<'EOF'
antidote() {
    case $1 in
        --version)
            print -r -- 'partial fixture antidote'
            return 0
            ;;
        path)
            if [[ -f $HOME/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme ]]; then
                print -r -- "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k"
                return 0
            fi
            return 1
            ;;
        bundle)
            [[ ! -f $PLASTICINE_TEST_BUNDLE_FAILS ]] || return 1
            mkdir -p "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k"
            print -r -- : > "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme"
            return 0
            ;;
        *) return 1 ;;
    esac
}
EOF
chmod +x "$partial_bin"/*
if PATH=$release_bin:$partial_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$partial/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$partial/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$partial/config/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$partial/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64 \
    PLASTICINE_SHELL_OS=Linux PLASTICINE_SHELL_ARCH=x86_64 PLASTICINE_SHELL_OS_RELEASE=$partial/os-release PLASTICINE_SHELL_ZSH=$real_zsh \
    PLASTICINE_SHELL_TTY=0 PLASTICINE_TEST_BUNDLE_FAILS=$partial/bundle-fails PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$partial/calls \
    "$repo_dir/install.sh" -y --lazygit --shell >/dev/null 2>"$partial/first-err"; then
    fail 'later shell failure was treated as success'
fi
if [ ! -x "$partial/home/.local/bin/lazygit" ]; then
    cat "$partial/first-err" >&2
    fail 'partial success did not retain healthy Lazygit'
fi
test ! -e "$partial/home/.zshrc" || fail 'partial failure applied combined configuration'
rm "$partial/bundle-fails"; : > "$partial/calls"
PATH=$release_bin:$partial_bin:/usr/bin:/bin PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo PLASTICINE_CHEZMOI_SOURCE_DIR=$partial/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$partial/config/chezmoi.toml PLASTICINE_CHEZMOI_STATE_FILE=$partial/config/state \
    PLASTICINE_CHEZMOI_DEST_DIR=$partial/home PLASTICINE_LAZYGIT_OS=Linux PLASTICINE_LAZYGIT_ARCH=x86_64 \
    PLASTICINE_SHELL_OS=Linux PLASTICINE_SHELL_ARCH=x86_64 PLASTICINE_SHELL_OS_RELEASE=$partial/os-release PLASTICINE_SHELL_ZSH=$real_zsh \
    PLASTICINE_SHELL_TTY=0 PLASTICINE_TEST_BUNDLE_FAILS=$partial/bundle-fails PLASTICINE_TEST_RELEASE_FIXTURE=$release_fixture PLASTICINE_TEST_RELEASE_CALLS=$partial/calls \
    "$repo_dir/install.sh" -y --lazygit --shell >/dev/null
test ! -s "$partial/calls" || fail 'partial-success rerun redownloaded healthy Lazygit'
test -f "$partial/home/.zshrc" || fail 'partial-success rerun did not apply configuration'

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
