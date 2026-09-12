#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [ -n "${CHEZMOI_BIN:-}" ]; then
    chezmoi_bin=$CHEZMOI_BIN
elif command -v chezmoi >/dev/null 2>&1; then
    chezmoi_bin=$(command -v chezmoi)
else
    printf '%s\n' '请通过 CHEZMOI_BIN 指定 chezmoi，或将 chezmoi 加入 PATH。' >&2
    exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-installer-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

work_repo=$test_root/work
mkdir -p "$work_repo"
for entry in "$repo_dir"/* "$repo_dir"/.[!.]*; do
    [ -e "$entry" ] || continue
    [ "${entry##*/}" = .git ] && continue
    cp -R "$entry" "$work_repo/"
done
git -C "$work_repo" init -q
git -C "$work_repo" symbolic-ref HEAD refs/heads/main
git -C "$work_repo" add -A
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm installer-test
origin_repo=$test_root/origin.git
git clone -q --bare "$work_repo" "$origin_repo"

protect_bin=$test_root/protect-bin
mkdir -p "$protect_bin"
protect_prefix=$test_root/protect-prefix/antidote
cat > "$protect_bin/brew" <<EOF
#!/bin/sh
case "\$*" in
    --version) exit 0 ;;
    '--prefix antidote')
        printf '%s\\n' '$protect_prefix'
        exit 0
        ;;
    *)
        printf '%s\\n' "plasticine tests: host brew blocked: \$*" >&2
        exit 99
        ;;
esac
EOF
for blocked in apt-get sudo chsh; do
    cat > "$protect_bin/$blocked" <<EOF
#!/bin/sh
printf '%s\\n' 'plasticine tests: host $blocked blocked' >&2
exit 99
EOF
done
cat > "$protect_bin/dscl" <<'EOF'
#!/bin/sh
printf 'UserShell: /bin/zsh\n'
EOF
cat > "$protect_bin/getent" <<'EOF'
#!/bin/sh
[ "${1:-}" = passwd ] || exit 99
printf 'owner:x:%s:%s:Owner:%s:/bin/zsh\n' "$(id -u)" "$(id -u)" "${HOME:-/tmp}"
EOF
cat > "$protect_bin/xcode-select" <<'EOF'
#!/bin/sh
[ "$*" = -p ] || exit 99
exit 0
EOF
chmod +x "$protect_bin"/*

run_installer() {
    scenario_dir=$1
    shift
    PATH=$protect_bin:$PATH \
    PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario_dir/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario_dir/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$scenario_dir/config/chezmoistate.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario_dir/home \
        "$repo_dir/install.sh" "$@"
}

empty_dir=$test_root/empty
mkdir -p "$empty_dir/home"
run_installer "$empty_dir" -y
test -d "$empty_dir/data/chezmoi/.git"
test -f "$empty_dir/config/chezmoi.toml"
grep -Fq 'tools = []' "$empty_dir/config/chezmoi.toml"
test ! -e "$empty_dir/home/.ssh"
test ! -e "$empty_dir/home/install.sh"

new_work=$test_root/new-work
git clone -q "$origin_repo" "$new_work"
printf 'installer update probe\n' >> "$new_work/README.md"
git -C "$new_work" add README.md
git -C "$new_work" -c user.name=test -c user.email=test@example.com commit -qm update-probe
git -C "$new_work" push -q origin HEAD:main
expected_head=$(git -C "$new_work" rev-parse HEAD)
run_installer "$empty_dir" -y
test "$(git -C "$empty_dir/data/chezmoi" rev-parse HEAD)" = "$expected_head"

ssh_dir=$test_root/ssh
mkdir -p "$ssh_dir/home/.ssh" "$ssh_dir/key dir"
printf 'Host example.com\n    User tester\n' > "$ssh_dir/home/.ssh/config"
key_path=$(printf "%s/key dir/key's-ed25519" "$ssh_dir")
ssh-keygen -q -t ed25519 -N '' -C installer-test -f "$key_path"
run_installer "$ssh_dir" -y --github-ssh --github-ssh-key "$key_path"
cmp -s "$key_path" "$ssh_dir/home/.ssh/id_github"
test -f "$ssh_dir/home/.ssh/config.d/00-plasticine-github.conf"
test -f "$ssh_dir/home/.ssh/config.plasticine-backup-before-managed"
before=$(find "$ssh_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
run_installer "$ssh_dir" -y --github-ssh --github-ssh-key "$key_path"
after=$(find "$ssh_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
test "$before" = "$after"

replace_dir=$test_root/replace
mkdir -p "$replace_dir/home/.ssh" "$replace_dir/key-dir"
ssh-keygen -q -t ed25519 -N '' -C installer-old -f "$replace_dir/home/.ssh/id_github"
old_fingerprint=$(ssh-keygen -lf "$replace_dir/home/.ssh/id_github" | awk '{ print $2 }')
replace_key=$replace_dir/key-dir/id_ed25519
ssh-keygen -q -t ed25519 -N '' -C installer-new -f "$replace_key"
if run_installer "$replace_dir" -y --github-ssh --github-ssh-key "$replace_key" >/dev/null 2>&1; then
    printf '%s\n' 'Replacing a key without explicit permission was not rejected.' >&2
    exit 1
fi
test "$(ssh-keygen -lf "$replace_dir/home/.ssh/id_github" | awk '{ print $2 }')" = "$old_fingerprint"
run_installer "$replace_dir" -y --github-ssh --github-ssh-key "$replace_key" --replace-github-ssh-key
cmp -s "$replace_key" "$replace_dir/home/.ssh/id_github"
backup_key=$(find "$replace_dir/home/.ssh" -name 'id_github.plasticine-backup-*')
test "$(ssh-keygen -lf "$backup_key" | awk '{ print $2 }')" = "$old_fingerprint"

missing_key_dir=$test_root/missing-key
mkdir -p "$missing_key_dir/home"
if run_installer "$missing_key_dir" -y --github-ssh >/dev/null 2>&1; then
    printf '%s\n' 'Missing --github-ssh-key was not rejected.' >&2
    exit 1
fi
test ! -e "$missing_key_dir/data/chezmoi"

foreign_dir=$test_root/foreign
mkdir -p "$foreign_dir/home" "$foreign_dir/data/chezmoi"
git -C "$foreign_dir/data/chezmoi" init -q
git -C "$foreign_dir/data/chezmoi" remote add origin https://example.com/other.git
if run_installer "$foreign_dir" -y >/dev/null 2>&1; then
    printf '%s\n' 'A foreign chezmoi source was not rejected.' >&2
    exit 1
fi
test ! -e "$foreign_dir/config/chezmoi.toml"

dirty_dir=$test_root/dirty
mkdir -p "$dirty_dir/home" "$dirty_dir/data"
git clone -q "$origin_repo" "$dirty_dir/data/chezmoi"
printf 'dirty\n' >> "$dirty_dir/data/chezmoi/README.md"
if run_installer "$dirty_dir" -y >/dev/null 2>&1; then
    printf '%s\n' 'A dirty chezmoi source was not rejected.' >&2
    exit 1
fi
test ! -e "$dirty_dir/config/chezmoi.toml"

no_tty_dir=$test_root/no-tty
mkdir -p "$no_tty_dir/home"
if run_installer "$no_tty_dir" </dev/null >/dev/null 2>&1; then
    printf '%s\n' 'Interactive mode without a TTY was not rejected.' >&2
    exit 1
fi
test ! -e "$no_tty_dir/data/chezmoi"

if command -v expect >/dev/null 2>&1; then
    interactive_dir=$test_root/interactive
    mkdir -p "$interactive_dir/home" "$interactive_dir/key-dir"
    interactive_key=$interactive_dir/key-dir/id_ed25519
    ssh-keygen -q -t ed25519 -N '' -C installer-interactive -f "$interactive_key"
    export PLASTICINE_TEST_INSTALLER="$repo_dir/install.sh"
    export PLASTICINE_TEST_CHEZMOI="$chezmoi_bin"
    export PLASTICINE_TEST_ORIGIN="$origin_repo"
    export PLASTICINE_TEST_SCENARIO="$interactive_dir"
    export PLASTICINE_TEST_KEY="$interactive_key"
    export PLASTICINE_TEST_PROTECT="$protect_bin"
    expect <<'EOF'
set timeout 20
set scenario $env(PLASTICINE_TEST_SCENARIO)
set env(PLASTICINE_CHEZMOI_BIN) $env(PLASTICINE_TEST_CHEZMOI)
set env(PLASTICINE_DOTFILES_REPO_URL) $env(PLASTICINE_TEST_ORIGIN)
set env(PLASTICINE_CHEZMOI_SOURCE_DIR) $scenario/data/chezmoi
set env(PLASTICINE_CHEZMOI_CONFIG_FILE) $scenario/config/chezmoi.toml
set env(PLASTICINE_CHEZMOI_STATE_FILE) $scenario/config/chezmoistate.boltdb
set env(PLASTICINE_CHEZMOI_DEST_DIR) $scenario/home
set env(PATH) "$env(PLASTICINE_TEST_PROTECT):$env(PATH)"
spawn $env(PLASTICINE_TEST_INSTALLER)
expect "选择要处理的工具"
after 300
send " "
after 200
send "\033\[B"
after 200
send " "
after 200
send "\r"
expect "GitHub SSH 私钥路径"
after 300
send -- "$env(PLASTICINE_TEST_KEY)\r"
expect "配置完成后测试 GitHub SSH 连接"
after 300
send "n\r"
expect "Apply these changes?"
after 300
send "n\r"
expect eof
catch wait result
exit [lindex $result 3]
EOF
    grep -Fq 'tools = ["github-ssh","shell"]' "$interactive_dir/config/chezmoi.toml"
    # Cancelling the final confirmation applies nothing from either selected tool
    # and never moves on to the shell toolchain or the login-shell transition.
    test ! -e "$interactive_dir/home/.ssh/id_github"
    test ! -e "$interactive_dir/home/.ssh/config.d"
    test ! -e "$interactive_dir/home/.zshrc"
    test ! -e "$interactive_dir/home/.zsh_plugins.txt"
    test ! -e "$interactive_dir/home/.p10k.zsh"
    test ! -e "$interactive_dir/home/.plasticine"
else
    printf '%s\n' 'installer tests: expect 不可用，跳过交互式选择与取消验证。' >&2
fi

printf '%s\n' 'installer tests passed'
