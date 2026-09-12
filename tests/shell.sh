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
if ! command -v zsh >/dev/null 2>&1; then
    printf '%s\n' 'shell 迁移测试需要真实的 zsh。' >&2
    exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-shell-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

# Build a compilable origin from the working tree, including untracked files.
work_repo=$test_root/work
mkdir -p "$work_repo"
find "$repo_dir" -mindepth 1 -maxdepth 1 ! -name .git -exec cp -R {} "$work_repo/" \;
git -C "$work_repo" init -q
git -C "$work_repo" symbolic-ref HEAD refs/heads/main
git -C "$work_repo" add -A
git -C "$work_repo" -c user.name=test -c user.email=test@example.com commit -qm shell-test
origin_repo=$test_root/origin.git
git clone -q --bare "$work_repo" "$origin_repo"

block_file=$test_root/block
cat > "$block_file" <<'EOF'
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

protect_bin=$test_root/protect-bin
mkdir -p "$protect_bin"
real_git=$(command -v git)
real_curl=$(command -v curl)
protect_prefix=$test_root/protect-prefix/antidote
cat > "$protect_bin/git" <<EOF
#!/bin/sh
if [ "\${1:-}" = clone ] && [ "\${2:-}" = --depth=1 ] &&
    [ "\${3:-}" = https://github.com/mattmc3/antidote.git ]; then
    printf '%s\\n' 'plasticine tests: host git clone of Antidote blocked' >&2
    exit 99
fi
exec '$real_git' "\$@"
EOF
cat > "$protect_bin/curl" <<EOF
#!/bin/sh
case " \$* " in
    *'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'*)
        printf '%s\\n' 'plasticine tests: host Homebrew installer download blocked' >&2
        exit 99
        ;;
esac
exec '$real_curl' "\$@"
EOF
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
login=$PLASTICINE_TEST_LOGIN_SHELL
if [ -z "$login" ]; then
    login=$(command -v zsh 2>/dev/null || true)
fi
[ -n "$login" ] || login=/bin/zsh
printf 'UserShell: %s\n' "$login"
EOF
cat > "$protect_bin/getent" <<'EOF'
#!/bin/sh
[ "${1:-}" = passwd ] || exit 99
login=$PLASTICINE_TEST_LOGIN_SHELL
if [ -z "$login" ]; then
    login=$(command -v zsh 2>/dev/null || true)
fi
[ -n "$login" ] || login=/bin/zsh
printf 'owner:x:%s:%s:Owner:%s:%s\n' "$(id -u)" "$(id -u)" "${HOME:-/tmp}" "$login"
EOF
cat > "$protect_bin/xcode-select" <<'EOF'
#!/bin/sh
[ "$*" = -p ] || exit 99
exit 0
EOF
chmod +x "$protect_bin"/*

scenario_path=''
run_installer() {
    scenario_dir=$1
    shift
    installer_status=0
    PATH=${scenario_path:+$scenario_path:}$protect_bin:$PATH \
    PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario_dir/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario_dir/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$scenario_dir/config/chezmoistate.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario_dir/home \
        "$repo_dir/install.sh" "$@" || installer_status=$?
    # Prefix assignments on functions persist in POSIX sh; do not leak seams.
    unset PLASTICINE_SHELL_HIDE_ZSH PLASTICINE_SHELL_HIDE_BREW PLASTICINE_SHELL_OS \
        PLASTICINE_SHELL_ARCH PLASTICINE_SHELL_OS_RELEASE PLASTICINE_SHELL_ZSH \
        PLASTICINE_SHELL_APT_ZSH PLASTICINE_SHELL_SYSTEM_ZSH PLASTICINE_SHELL_TTY \
        PLASTICINE_SHELL_MACOS_VERSION PLASTICINE_SHELL_HOMEBREW_ARM \
        PLASTICINE_SHELL_HOMEBREW_INTEL PLASTICINE_TEST_LOGIN_SHELL \
        PLASTICINE_TEST_BUNDLE_FAILS PLASTICINE_TEST_CALLS
    return "$installer_status"
}

write_antidote() {
    antidote_home=$1
    mkdir -p "$antidote_home/.antidote"
    if [ "${2:-}" != missing-p10k ]; then
        mkdir -p "$antidote_home/.cache/antidote/github.com/romkatv/powerlevel10k"
        printf '%s\n' ':' > "$antidote_home/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme"
    fi
    cat > "$antidote_home/.antidote/antidote.zsh" <<'EOF'
antidote() {
    case $1 in
        --version)
            print -r -- 'plasticine shell test antidote'
            return 0
            ;;
        path)
            if [[ $2 == romkatv/powerlevel10k &&
                -f $HOME/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme ]]; then
                print -r -- "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k"
                return 0
            fi
            return 1
            ;;
        bundle)
            if [[ $* == 'bundle romkatv/powerlevel10k kind:clone' ]]; then
                print -r -- 'bundle romkatv/powerlevel10k kind:clone' >> "${PLASTICINE_TEST_CALLS:-/dev/null}"
                if [[ -n ${PLASTICINE_TEST_BUNDLE_FAILS:-} && -e $PLASTICINE_TEST_BUNDLE_FAILS ]]; then
                    return 1
                fi
                mkdir -p "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k"
                print -r -- ':' > "$HOME/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme"
                return 0
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}
EOF
}

file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

fail() {
    printf '%s\n' "shell tests: $1" >&2
    exit 1
}

debian_release=$test_root/os-release
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$debian_release"

run_linux_installer() {
    PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=${PLASTICINE_SHELL_ARCH:-arm64} \
    PLASTICINE_SHELL_OS_RELEASE=${PLASTICINE_SHELL_OS_RELEASE:-$debian_release} \
    run_installer "$@"
}

# --shell without -y follows the existing tool-option rule and stops early.
missing_y_dir=$test_root/missing-y
mkdir -p "$missing_y_dir/home"
if run_installer "$missing_y_dir" --shell </dev/null >/dev/null 2>&1; then
    fail '--shell without -y was not rejected.'
fi
test ! -e "$missing_y_dir/data/chezmoi"

# Leaving shell unselected applies nothing shell-owned and probes nothing.
empty_dir=$test_root/empty
mkdir -p "$empty_dir/home" "$empty_dir/fake-bin"
probe_marker=$empty_dir/probed
cat > "$empty_dir/fake-bin/zsh" <<EOF
#!/bin/sh
printf 'probed\n' >> '$probe_marker'
exit 1
EOF
chmod +x "$empty_dir/fake-bin/zsh"
if ! scenario_path="$empty_dir/fake-bin" run_installer "$empty_dir" -y \
    >"$empty_dir/out" 2>"$empty_dir/err"; then
    tail -20 "$empty_dir/out" >&2
    cat "$empty_dir/err" >&2
    fail 'empty selection apply failed'
fi
scenario_path=''
grep -Fq 'tools = []' "$empty_dir/config/chezmoi.toml" || fail 'empty selection did not record tools = [].'
test ! -e "$probe_marker" || fail 'empty selection probed zsh.'
test ! -e "$empty_dir/home/.zshrc" || fail 'empty selection wrote .zshrc.'
test ! -e "$empty_dir/home/.zsh_plugins.txt" || fail 'empty selection wrote plugins.'
test ! -e "$empty_dir/home/.p10k.zsh" || fail 'empty selection wrote p10k.'
test ! -e "$empty_dir/home/.plasticine" || fail 'empty selection wrote .plasticine.'

# An existing healthy Zsh and Antidote are enough for the configuration seam.
shell_dir=$test_root/shell-only
mkdir -p "$shell_dir/home"
write_antidote "$shell_dir/home"
if ! run_linux_installer "$shell_dir" -y --shell >"$shell_dir/out" 2>"$shell_dir/err"; then
    tail -20 "$shell_dir/out" >&2
    cat "$shell_dir/err" >&2
    fail 'shell-only apply failed'
fi
grep -Fq 'tools = ["shell"]' "$shell_dir/config/chezmoi.toml" || fail 'shell-only did not record tools = ["shell"].'
cmp -s "$block_file" "$shell_dir/home/.zshrc" || fail 'shell-only did not apply .zshrc.'
cmp -s "$repo_dir/dot_zsh_plugins.txt" "$shell_dir/home/.zsh_plugins.txt" || fail 'shell-only did not apply plugins.'
cmp -s "$repo_dir/dot_p10k.zsh" "$shell_dir/home/.p10k.zsh" || fail 'shell-only did not apply p10k.'
cmp -s "$repo_dir/dot_plasticine/zsh/shared.zsh" "$shell_dir/home/.plasticine/zsh/shared.zsh" || fail 'shell-only did not apply shared.zsh.'
for target in .zshrc .zsh_plugins.txt .p10k.zsh .plasticine/zsh/shared.zsh; do
    test "$(file_mode "$shell_dir/home/$target")" = 644 ||
        fail "shell-only $target mode is $(file_mode "$shell_dir/home/$target")"
done
if [ -e "$shell_dir/home/.plasticine/backups" ]; then
    find "$shell_dir/home/.plasticine/backups" >&2
    fail 'shell-only created backups for a fresh destination.'
fi

# shell and github-ssh compose into one unordered selection set.
combined_dir=$test_root/combined
mkdir -p "$combined_dir/home" "$combined_dir/key-dir"
write_antidote "$combined_dir/home"
combined_key=$combined_dir/key-dir/id_ed25519
ssh-keygen -q -t ed25519 -N '' -C shell-test -f "$combined_key"
if ! run_linux_installer "$combined_dir" -y --shell --github-ssh --github-ssh-key "$combined_key" \
    >"$combined_dir/out" 2>"$combined_dir/err"; then
    tail -20 "$combined_dir/out" >&2
    cat "$combined_dir/err" >&2
    fail 'combined apply failed'
fi
tools_line=$(grep 'tools = ' "$combined_dir/config/chezmoi.toml" || true)
printf '%s\n' "$tools_line" | grep -Fq 'tools = ["github-ssh","shell"]' ||
    fail "combined tools line: $tools_line"
cmp -s "$combined_key" "$combined_dir/home/.ssh/id_github" || fail 'combined did not copy the GitHub SSH key.'
test -f "$combined_dir/home/.ssh/config.d/00-plasticine-github.conf" || fail 'combined did not write SSH config.'
cmp -s "$block_file" "$combined_dir/home/.zshrc" || fail 'combined did not apply the shell block.'
cmp -s "$repo_dir/dot_zsh_plugins.txt" "$combined_dir/home/.zsh_plugins.txt" || fail 'combined did not apply plugins.'

# Missing Antidote uses Homebrew on Darwin even when a leftover ~/.antidote exists.
missing_antidote_dir=$test_root/missing-antidote
mkdir -p "$missing_antidote_dir/home/.antidote" "$missing_antidote_dir/fake-bin"
printf '%s\n' leftover > "$missing_antidote_dir/home/.antidote/README"
missing_antidote_prefix=$missing_antidote_dir/prefix
cat > "$missing_antidote_dir/fake-bin/brew" <<EOF
#!/bin/sh
[ "\$HOMEBREW_NO_ANALYTICS" = 1 ] || exit 99
case "\$*" in
    --version) exit 0 ;;
    '--prefix antidote')
        printf '%s\\n' '$missing_antidote_prefix'
        ;;
    'install antidote')
        printf 'brew install antidote\\n' >> '$missing_antidote_dir/fake-bin/calls'
        mkdir -p '$missing_antidote_prefix/share/antidote'
        cp '$missing_antidote_dir/antidote.zsh' '$missing_antidote_prefix/share/antidote/antidote.zsh'
        ;;
    *) exit 99 ;;
esac
EOF
chmod +x "$missing_antidote_dir/fake-bin/brew"
write_antidote "$missing_antidote_dir/fixture"
cp "$missing_antidote_dir/fixture/.antidote/antidote.zsh" "$missing_antidote_dir/antidote.zsh"
: > "$missing_antidote_dir/fake-bin/calls"
if ! PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_TEST_LOGIN_SHELL=/bin/zsh \
    scenario_path="$missing_antidote_dir/fake-bin" \
    run_installer "$missing_antidote_dir" -y --shell \
    >"$missing_antidote_dir/stdout" 2>"$missing_antidote_dir/stderr"; then
    tail -50 "$missing_antidote_dir/stdout" >&2
    cat "$missing_antidote_dir/stderr" >&2
    cat "$missing_antidote_dir/fake-bin/calls" >&2
    fail 'missing Antidote brew route failed'
fi
scenario_path=''
if ! grep -Fq 'brew install antidote' "$missing_antidote_dir/fake-bin/calls"; then
    cat "$missing_antidote_dir/stdout" >&2
    cat "$missing_antidote_dir/stderr" >&2
    cat "$missing_antidote_dir/fake-bin/calls" >&2
    fail 'missing Antidote did not use the Homebrew route'
fi
if grep -Fq 'git clone' "$missing_antidote_dir/fake-bin/calls"; then
    fail 'Darwin missing Antidote fell back to git clone.'
fi
test -f "$missing_antidote_prefix/share/antidote/antidote.zsh" || fail 'Homebrew Antidote prefix was not created.'
test -f "$missing_antidote_dir/home/.antidote/README" || fail 'Darwin Homebrew route mutated ~/.antidote.'
cmp -s "$block_file" "$missing_antidote_dir/home/.zshrc" || fail 'missing Antidote did not apply .zshrc.'
cmp -s "$repo_dir/dot_zsh_plugins.txt" "$missing_antidote_dir/home/.zsh_plugins.txt" || fail 'missing Antidote did not apply plugins.'

unhealthy_antidote_dir=$test_root/unhealthy-antidote
mkdir -p "$unhealthy_antidote_dir/home/.antidote"
cat > "$unhealthy_antidote_dir/home/.antidote/antidote.zsh" <<'EOF'
antidote() {
    return 1
}
EOF
if run_linux_installer "$unhealthy_antidote_dir" -y --shell \
    >"$unhealthy_antidote_dir/stdout" 2>"$unhealthy_antidote_dir/stderr"; then
    fail 'Unhealthy Antidote was not rejected.'
fi
grep -Fq 'Antidote' "$unhealthy_antidote_dir/stderr"
test ! -e "$unhealthy_antidote_dir/home/.zshrc"

unhealthy_zsh_dir=$test_root/unhealthy-zsh
mkdir -p "$unhealthy_zsh_dir/home" "$unhealthy_zsh_dir/fake-bin"
write_antidote "$unhealthy_zsh_dir/home"
cat > "$unhealthy_zsh_dir/fake-bin/zsh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$unhealthy_zsh_dir/fake-bin/zsh"
if scenario_path="$unhealthy_zsh_dir/fake-bin" \
    run_linux_installer "$unhealthy_zsh_dir" -y --shell \
    >"$unhealthy_zsh_dir/stdout" 2>"$unhealthy_zsh_dir/stderr"; then
    fail 'Unhealthy Zsh was not rejected.'
fi
scenario_path=''
grep -Fq 'Zsh' "$unhealthy_zsh_dir/stderr"
test ! -e "$unhealthy_zsh_dir/home/.zshrc"

# Missing block is inserted at the beginning; every outside byte survives.
preserve_dir=$test_root/preserve
mkdir -p "$preserve_dir/home"
write_antidote "$preserve_dir/home"
printf '# Owner\015\012\303\251\000\377\011tail' > "$preserve_dir/home/.zshrc"
if ! run_linux_installer "$preserve_dir" -y --shell >"$preserve_dir/out" 2>"$preserve_dir/err"; then
    tail -40 "$preserve_dir/out" >&2
    cat "$preserve_dir/err" >&2
    fail 'preserve apply failed'
fi
cat "$block_file" > "$preserve_dir/expected"
printf '# Owner\015\012\303\251\000\377\011tail' >> "$preserve_dir/expected"
cmp -s "$preserve_dir/expected" "$preserve_dir/home/.zshrc" || fail 'preserve did not keep outside .zshrc bytes.'

# A valid existing block is replaced in place and backed up.
replace_dir=$test_root/replace
mkdir -p "$replace_dir/home"
write_antidote "$replace_dir/home"
printf 'pre\015\012# >>> Plasticine shell >>>\012old body\012# <<< Plasticine shell <<<\012suf\000\377' \
    > "$replace_dir/home/.zshrc"
cp "$replace_dir/home/.zshrc" "$replace_dir/before"
chmod 640 "$replace_dir/home/.zshrc"
if ! run_linux_installer "$replace_dir" -y --shell >"$replace_dir/out" 2>"$replace_dir/err"; then
    cat "$replace_dir/out" >&2
    cat "$replace_dir/err" >&2
    fail 'replace apply failed'
fi
printf 'pre\015\012' > "$replace_dir/expected"
cat "$block_file" >> "$replace_dir/expected"
printf 'suf\000\377' >> "$replace_dir/expected"
cmp -s "$replace_dir/expected" "$replace_dir/home/.zshrc" || fail 'replace did not preserve outside .zshrc bytes.'
test "$(file_mode "$replace_dir/home/.zshrc")" = 640 ||
    fail "replace zshrc mode is $(file_mode "$replace_dir/home/.zshrc")"
backup_file=$(find "$replace_dir/home/.plasticine/backups/shell" -name '.zshrc.plasticine-backup-*')
test -n "$backup_file" || fail 'replace did not back up .zshrc.'
cmp -s "$replace_dir/before" "$backup_file" || fail 'replace backup does not match the original .zshrc.'
test "$(file_mode "$backup_file")" = 600 || fail "replace backup mode is $(file_mode "$backup_file")"

# Malformed selected markers fail before any mutation.
malformed_index=0
for malformed in \
    'begin' \
    'end' \
    'reversed' \
    'duplicate-begin' \
    'duplicate-block' \
    'damaged' \
    'indented' \
    'crlf'; do
    malformed_index=$((malformed_index + 1))
    malformed_dir=$test_root/malformed-$malformed_index
    mkdir -p "$malformed_dir/home"
    write_antidote "$malformed_dir/home"
    case $malformed in
        begin) printf '# >>> Plasticine shell >>>\012' > "$malformed_dir/home/.zshrc" ;;
        end) printf '# <<< Plasticine shell <<<\012' > "$malformed_dir/home/.zshrc" ;;
        reversed) printf '# <<< Plasticine shell <<<\012# >>> Plasticine shell >>>\012' > "$malformed_dir/home/.zshrc" ;;
        duplicate-begin)
            printf '# >>> Plasticine shell >>>\012# >>> Plasticine shell >>>\012# <<< Plasticine shell <<<\012' \
                > "$malformed_dir/home/.zshrc"
            ;;
        duplicate-block)
            cat "$block_file" "$block_file" > "$malformed_dir/home/.zshrc"
            ;;
        damaged) printf '# >>> Plasticine shell >>\012' > "$malformed_dir/home/.zshrc" ;;
        indented) printf '  # >>> Plasticine shell >>>\012# <<< Plasticine shell <<<\012' > "$malformed_dir/home/.zshrc" ;;
        crlf) printf '# >>> Plasticine shell >>>\015\012# <<< Plasticine shell <<<\012' > "$malformed_dir/home/.zshrc" ;;
    esac
    cp "$malformed_dir/home/.zshrc" "$malformed_dir/before"
    if run_linux_installer "$malformed_dir" -y --shell \
        >"$malformed_dir/stdout" 2>"$malformed_dir/stderr"; then
        fail "Malformed markers ($malformed) were not rejected."
    fi
    cmp -s "$malformed_dir/before" "$malformed_dir/home/.zshrc" ||
        fail "Malformed markers ($malformed) changed ~/.zshrc."
    test ! -e "$malformed_dir/home/.zsh_plugins.txt"
    test ! -e "$malformed_dir/home/.plasticine/backups"
done

# Non-regular targets and symlinked parents are rejected before effects.
unsafe_index=0
for target in .zshrc .zsh_plugins.txt .p10k.zsh .plasticine/zsh/shared.zsh; do
    for kind in symlink dangling directory fifo; do
        unsafe_index=$((unsafe_index + 1))
        unsafe_dir=$test_root/unsafe-$unsafe_index
        mkdir -p "$unsafe_dir/home"
        write_antidote "$unsafe_dir/home"
        unsafe_target=$unsafe_dir/home/$target
        mkdir -p "${unsafe_target%/*}"
        case $kind in
            symlink) ln -s "$unsafe_dir/elsewhere" "$unsafe_target" ;;
            dangling) ln -s "$unsafe_dir/nowhere" "$unsafe_target" ;;
            directory) mkdir "$unsafe_target" ;;
            fifo) mkfifo "$unsafe_target" ;;
        esac
        if run_linux_installer "$unsafe_dir" -y --shell \
            >"$unsafe_dir/stdout" 2>"$unsafe_dir/stderr"; then
            fail "Non-regular target ($target, $kind) was not rejected."
        fi
        case $kind in
            symlink|dangling) test -L "$unsafe_target" || fail "$target $kind was replaced." ;;
            directory) test -d "$unsafe_target" && test ! -L "$unsafe_target" || fail "$target directory was replaced." ;;
            fifo) test -p "$unsafe_target" || fail "$target fifo was replaced." ;;
        esac
        test ! -e "$unsafe_dir/home/.zshrc" || [ "$target" = .zshrc ] ||
            fail "Unsafe target $target still applied ~/.zshrc."
    done
done

symlinked_parent_dir=$test_root/symlinked-parent
mkdir -p "$symlinked_parent_dir/home" "$symlinked_parent_dir/real-plasticine"
write_antidote "$symlinked_parent_dir/home"
ln -s "$symlinked_parent_dir/real-plasticine" "$symlinked_parent_dir/home/.plasticine"
if run_linux_installer "$symlinked_parent_dir" -y --shell \
    >"$symlinked_parent_dir/stdout" 2>"$symlinked_parent_dir/stderr"; then
    fail 'Symlinked ~/.plasticine parent was not rejected.'
fi
test -L "$symlinked_parent_dir/home/.plasticine"
test ! -e "$symlinked_parent_dir/home/.zshrc"

# Unknown selected tools fail before apply.
unknown_dir=$test_root/unknown
mkdir -p "$unknown_dir/home"
if PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS='shell bogus' \
    "$chezmoi_bin" \
    -S "$work_repo" \
    -D "$unknown_dir/home" \
    -C "$unknown_dir/chezmoi.toml" \
    --persistent-state "$unknown_dir/state.boltdb" \
    init >"$unknown_dir/stdout" 2>"$unknown_dir/stderr"; then
    fail 'Unknown selected tools were not rejected.'
fi
grep -Fq '不支持的工具' "$unknown_dir/stderr"
test ! -e "$unknown_dir/chezmoi.toml"

# A satisfied install converges without new writes or backups.
rerun_dir=$test_root/rerun
mkdir -p "$rerun_dir/home"
write_antidote "$rerun_dir/home"
printf 'owner zshrc\012' > "$rerun_dir/home/.zshrc"
chmod 640 "$rerun_dir/home/.zshrc"
printf 'owner plugins\012' > "$rerun_dir/home/.zsh_plugins.txt"
chmod 600 "$rerun_dir/home/.zsh_plugins.txt"
if ! run_linux_installer "$rerun_dir" -y --shell >"$rerun_dir/first.out" 2>"$rerun_dir/first.err"; then
    cat "$rerun_dir/first.out" >&2
    cat "$rerun_dir/first.err" >&2
    fail 'first rerun apply failed'
fi
test "$(file_mode "$rerun_dir/home/.zshrc")" = 640 ||
    fail "rerun zshrc mode is $(file_mode "$rerun_dir/home/.zshrc")"
test "$(file_mode "$rerun_dir/home/.zsh_plugins.txt")" = 600 ||
    fail "rerun plugins mode is $(file_mode "$rerun_dir/home/.zsh_plugins.txt")"
backup_count=$(find "$rerun_dir/home/.plasticine/backups/shell" -type f | wc -l | tr -d ' ')
if [ "$backup_count" -ne 2 ]; then
    find "$rerun_dir/home/.plasticine/backups/shell" -type f >&2
    fail "rerun backup count is $backup_count"
fi
find "$rerun_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort > "$rerun_dir/hash-before"
before=$(shasum -a 256 "$rerun_dir/hash-before" | awk '{ print $1 }')
run_linux_installer "$rerun_dir" -y --shell >/dev/null || fail 'satisfied rerun apply failed.'
find "$rerun_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort > "$rerun_dir/hash-after"
after=$(shasum -a 256 "$rerun_dir/hash-after" | awk '{ print $1 }')
if [ "$before" != "$after" ]; then
    diff -u "$rerun_dir/hash-before" "$rerun_dir/hash-after" >&2 || true
    fail 'Satisfied rerun changed destination files.'
fi
test "$(file_mode "$rerun_dir/home/.zshrc")" = 640 ||
    fail "rerun zshrc mode after retry is $(file_mode "$rerun_dir/home/.zshrc")"
test "$(file_mode "$rerun_dir/home/.zsh_plugins.txt")" = 600 ||
    fail "rerun plugins mode after retry is $(file_mode "$rerun_dir/home/.zsh_plugins.txt")"
backup_count=$(find "$rerun_dir/home/.plasticine/backups/shell" -type f | wc -l | tr -d ' ')
test "$backup_count" -eq 2 || fail "rerun backup count after retry is $backup_count"

write_bootstrap_bin() {
    fake_bin=$1
    mkdir -p "$fake_bin"
    : > "$fake_bin/calls"
    real_zsh=$(command -v zsh)
    cat > "$fake_bin/zsh.fixture" <<EOF
#!/bin/sh
[ ! -f '$fake_bin/zsh-fails' ] || exit 1
exec '$real_zsh' "\$@"
EOF
    chmod +x "$fake_bin/zsh.fixture"
    cat > "$fake_bin/antidote.fixture" <<EOF
antidote() {
    case \$1 in
        --version) return 0 ;;
        path)
            [[ -f "\$HOME/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme" ]] || return 1
            print -r -- "\$HOME/.cache/antidote/github.com/romkatv/powerlevel10k" ;;
        bundle)
            [[ "\$*" == 'bundle romkatv/powerlevel10k kind:clone' ]] || return 99
            print -r -- 'bundle romkatv/powerlevel10k kind:clone' >> '$fake_bin/calls'
            [[ ! -f '$fake_bin/bundle-fails' ]] || return 1
            mkdir -p "\$HOME/.cache/antidote/github.com/romkatv/powerlevel10k"
            print -r -- ':' > "\$HOME/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme" ;;
        *) return 99 ;;
    esac
}
EOF
    cat > "$fake_bin/git" <<EOF
#!/bin/sh
if [ "\$1" = --version ]; then
    [ ! -f '$fake_bin/git-unhealthy' ] || exit 1
    exec '$real_git' --version
fi
if [ "\$1" = clone ] && [ "\${2:-}" = --depth=1 ] &&
    [ "\${3:-}" = https://github.com/mattmc3/antidote.git ]; then
    printf 'git %s\\n' "\$*" >> '$fake_bin/calls'
    [ ! -f '$fake_bin/git-fails' ] || exit 1
    dest=\$4
    mkdir -p "\$dest"
    cp '$fake_bin/antidote.fixture' "\$dest/antidote.zsh"
    exit 0
fi
exec '$real_git' "\$@"
EOF
    cat > "$fake_bin/brew" <<EOF
#!/bin/sh
[ "\$HOMEBREW_NO_ANALYTICS" = 1 ] || exit 99
case "\$*" in
    --version)
        [ ! -f '$fake_bin/brew-unhealthy' ] || exit 1
        exit 0
        ;;
    '--prefix antidote')
        printf '%s\\n' '$fake_bin/prefix'
        ;;
    'install antidote')
        printf 'brew install antidote\\n' >> '$fake_bin/calls'
        [ ! -f '$fake_bin/brew-fails' ] || exit 1
        mkdir -p '$fake_bin/prefix/share/antidote'
        cp '$fake_bin/antidote.fixture' '$fake_bin/prefix/share/antidote/antidote.zsh'
        ;;
    *) exit 99 ;;
esac
EOF
    cat > "$fake_bin/apt-get" <<EOF
#!/bin/sh
printf 'apt-get %s\\n' "\$*" >> '$fake_bin/calls'
[ ! -f '$fake_bin/apt-fails' ] || exit 1
case \$1 in
    update) [ "\$#" = 1 ] || exit 99 ;;
    install)
        [ "\$2" = -y ] && [ "\$3" = --no-upgrade ] || exit 99
        shift 3
        for package do
            case \$package in
                zsh) cp '$fake_bin/zsh.fixture' '$fake_bin/zsh' ;;
                git) : ;;
                ca-certificates) : ;;
                *) exit 99 ;;
            esac
        done
        ;;
    *) exit 99 ;;
esac
EOF
    cat > "$fake_bin/sudo" <<EOF
#!/bin/sh
printf 'sudo %s\\n' "\$*" >> '$fake_bin/calls'
[ "\$1" != -n ] || shift
[ "\$1" = apt-get ] || { printf 'FORBIDDEN sudo\\n' >> '$fake_bin/calls'; exit 99; }
exec "\$@"
EOF
    cat > "$fake_bin/chsh" <<EOF
#!/bin/sh
[ "\$1" = -s ] && [ "\$#" = 2 ] || exit 99
for target in .plasticine/zsh/shared.zsh .zsh_plugins.txt .p10k.zsh .zshrc; do
    [ -s "\$PLASTICINE_CHEZMOI_DEST_DIR/\$target" ] || {
        printf 'FORBIDDEN chsh before files\\n' >> '$fake_bin/calls'
        exit 99
    }
done
printf 'chsh %s\\n' "\$*" >> '$fake_bin/calls'
[ ! -f '$fake_bin/chsh-fails' ] || exit 1
[ ! -f '$fake_bin/chsh-lies' ] || exit 0
printf '%s\\n' "\$2" > '$fake_bin/login'
EOF
    cat > "$fake_bin/dscl" <<EOF
#!/bin/sh
printf 'UserShell: %s\\n' "\$(cat '$fake_bin/login')"
EOF
    cat > "$fake_bin/getent" <<EOF
#!/bin/sh
[ "\$1" = passwd ] || exit 99
printf 'owner:x:%s:%s:Owner:%s:%s\\n' "\$(id -u)" "\$(id -u)" "\${HOME:-/tmp}" "\$(cat '$fake_bin/login')"
EOF
    cat > "$fake_bin/curl" <<EOF
#!/bin/sh
[ "\$*" = '-fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' ] || exit 99
printf 'curl official-homebrew\\n' >> '$fake_bin/calls'
[ ! -f '$fake_bin/curl-fails' ] || exit 1
printf '%s\\n' 'official-homebrew-fixture'
EOF
    cat > "$fake_bin/bash" <<EOF
#!/bin/sh
[ "\$1" = -c ] && [ "\$2" = official-homebrew-fixture ] || exit 99
[ -z "\${NONINTERACTIVE:-}" ] && [ -z "\${CI:-}" ] && [ "\$HOMEBREW_NO_ANALYTICS" = 1 ] || exit 99
printf 'bash official-homebrew unprivileged\\n' >> '$fake_bin/calls'
if [ -f '$fake_bin/brew.available' ]; then
    cp '$fake_bin/brew.available' '$fake_bin/brew'
fi
mkdir -p '$fake_bin/prefix'
EOF
    cat > "$fake_bin/xcode-select" <<EOF
#!/bin/sh
[ "\$*" = -p ] || exit 99
[ ! -f '$fake_bin/clt-fails' ]
EOF
    cat > "$fake_bin/sw_vers" <<EOF
#!/bin/sh
[ "\$1" = -productVersion ] || exit 99
printf '%s\\n' "\${PLASTICINE_SHELL_MACOS_VERSION:-14.0}"
EOF
    chmod +x "$fake_bin/git" "$fake_bin/brew" "$fake_bin/apt-get" "$fake_bin/sudo" \
        "$fake_bin/chsh" "$fake_bin/dscl" "$fake_bin/getent" "$fake_bin/curl" \
        "$fake_bin/bash" "$fake_bin/xcode-select" "$fake_bin/sw_vers"
}

expect_config() {
    cmp -s "$block_file" "$1/home/.zshrc" || fail "$2: ~/.zshrc was not applied."
    cmp -s "$repo_dir/dot_zsh_plugins.txt" "$1/home/.zsh_plugins.txt" || fail "$2: plugins were not applied."
    cmp -s "$repo_dir/dot_p10k.zsh" "$1/home/.p10k.zsh" || fail "$2: p10k was not applied."
    test -f "$1/home/.plasticine/zsh/shared.zsh" || fail "$2: shared.zsh was not applied."
}

expect_no_config() {
    test ! -e "$1/home/.zshrc" || fail "$2: ~/.zshrc was applied."
    test ! -e "$1/home/.zsh_plugins.txt" || fail "$2: plugins were applied."
}

# Missing Antidote on Linux uses the official Git checkout.
missing_antidote_linux=$test_root/missing-antidote-linux
mkdir -p "$missing_antidote_linux/home"
write_bootstrap_bin "$missing_antidote_linux/fake-bin"
cp "$missing_antidote_linux/fake-bin/zsh.fixture" "$missing_antidote_linux/fake-bin/zsh"
printf '%s\n' "$missing_antidote_linux/fake-bin/zsh" > "$missing_antidote_linux/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$missing_antidote_linux/os-release"
if ! PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$missing_antidote_linux/os-release \
    scenario_path=$missing_antidote_linux/fake-bin \
    run_installer "$missing_antidote_linux" -y --shell \
    >"$missing_antidote_linux/stdout" 2>"$missing_antidote_linux/stderr"; then
    cat "$missing_antidote_linux/stdout" >&2
    cat "$missing_antidote_linux/stderr" >&2
    fail 'missing Linux Antidote git route failed'
fi
scenario_path=''
grep -Fq 'git clone --depth=1 https://github.com/mattmc3/antidote.git' "$missing_antidote_linux/stdout" ||
    fail 'missing Linux Antidote preview omitted git clone.'
grep -Fq 'git clone --depth=1 https://github.com/mattmc3/antidote.git' "$missing_antidote_linux/fake-bin/calls" ||
    fail 'missing Linux Antidote did not clone Antidote.'
if grep -Fq 'brew install' "$missing_antidote_linux/fake-bin/calls"; then
    fail 'Linux missing Antidote used Homebrew.'
fi
expect_config "$missing_antidote_linux" 'missing Linux Antidote'

# Fresh Linux: APT Zsh, Git checkout Antidote, bundle p10k, then chsh.
linux_fresh=$test_root/linux-fresh
mkdir -p "$linux_fresh/home"
write_bootstrap_bin "$linux_fresh/fake-bin"
printf '%s\n' '/bin/bash' > "$linux_fresh/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_fresh/os-release"
linux_zsh=$linux_fresh/fake-bin/zsh
if ! PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_fresh/os-release \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_APT_ZSH=$linux_zsh \
    PLASTICINE_SHELL_TTY=1 \
    SHELL=/stale/environment/shell \
    scenario_path=$linux_fresh/fake-bin \
    run_installer "$linux_fresh" -y --shell \
    >"$linux_fresh/stdout" 2>"$linux_fresh/stderr"; then
    cat "$linux_fresh/stdout" >&2
    cat "$linux_fresh/stderr" >&2
    cat "$linux_fresh/fake-bin/calls" >&2
    fail 'fresh Linux bootstrap failed.'
fi
scenario_path=''
if ! grep -Fq 'Zsh route: apt' "$linux_fresh/stdout"; then
    cat "$linux_fresh/stdout" >&2
    cat "$linux_fresh/stderr" >&2
    fail 'fresh Linux preview missing apt route.'
fi
grep -Fq 'Antidote route: git' "$linux_fresh/stdout"
grep -Fq 'sudo apt-get update' "$linux_fresh/stdout"
grep -Fq 'sudo apt-get install -y --no-upgrade zsh' "$linux_fresh/stdout"
grep -Fq 'git clone --depth=1' "$linux_fresh/stdout"
grep -Fq 'antidote bundle romkatv/powerlevel10k kind:clone' "$linux_fresh/stdout"
grep -Fq 'LAST, after usable configuration: chsh' "$linux_fresh/stdout"
grep -Fq HTTPS "$linux_fresh/stdout"
grep -Fq privilege "$linux_fresh/stdout"
grep -Fq opaque "$linux_fresh/stdout"
linux_log=$(cat "$linux_fresh/fake-bin/calls")
printf '%s\n' "$linux_log" | grep -Fq 'sudo apt-get install -y --no-upgrade zsh'
printf '%s\n' "$linux_log" | grep -Fq 'git clone --depth=1 https://github.com/mattmc3/antidote.git'
printf '%s\n' "$linux_log" | grep -Fq 'bundle romkatv/powerlevel10k kind:clone'
printf '%s\n' "$linux_log" | grep -Fq "chsh -s $linux_zsh"
test "$(cat "$linux_fresh/fake-bin/login")" = "$linux_zsh"
expect_config "$linux_fresh" 'fresh Linux'
apt_at=$(printf '%s\n' "$linux_log" | grep -n 'apt-get install' | head -n1 | cut -d: -f1)
git_at=$(printf '%s\n' "$linux_log" | grep -n 'git clone' | head -n1 | cut -d: -f1)
bundle_at=$(printf '%s\n' "$linux_log" | grep -n 'bundle ' | head -n1 | cut -d: -f1)
chsh_at=$(printf '%s\n' "$linux_log" | grep -n 'chsh ' | head -n1 | cut -d: -f1)
test "$apt_at" -lt "$git_at"
test "$git_at" -lt "$bundle_at"
test "$bundle_at" -lt "$chsh_at"

# Healthy existing tools plus a correct login shell are a no-op, even with stale SHELL.
linux_rerun_before=$(find "$linux_fresh/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
: > "$linux_fresh/fake-bin/calls"
PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_fresh/os-release \
    PLASTICINE_SHELL_APT_ZSH=$linux_zsh \
    PLASTICINE_SHELL_TTY=0 \
    SHELL=/stale/environment/shell \
    scenario_path=$linux_fresh/fake-bin \
    run_installer "$linux_fresh" -y --shell \
    >"$linux_fresh/rerun-stdout" 2>"$linux_fresh/rerun-stderr"
scenario_path=''
linux_rerun_after=$(find "$linux_fresh/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
test "$linux_rerun_before" = "$linux_rerun_after"
if [ -s "$linux_fresh/fake-bin/calls" ]; then
    cat "$linux_fresh/fake-bin/calls" >&2
    fail 'healthy Linux rerun invoked installers'
fi
grep -Fq already-present "$linux_fresh/rerun-stdout" || fail 'healthy rerun preview missing already-present.'
grep -Fq 'no chsh call' "$linux_fresh/rerun-stdout" || fail 'healthy rerun preview still proposed chsh.'

# Denied chsh keeps usable files; a later rerun retries only the transition.
linux_chsh_fail=$test_root/linux-chsh-fail
mkdir -p "$linux_chsh_fail/home"
write_bootstrap_bin "$linux_chsh_fail/fake-bin"
write_antidote "$linux_chsh_fail/home"
printf '%s\n' '/bin/bash' > "$linux_chsh_fail/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_chsh_fail/os-release"
: > "$linux_chsh_fail/fake-bin/chsh-fails"
cp "$linux_chsh_fail/fake-bin/zsh.fixture" "$linux_chsh_fail/fake-bin/zsh"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_chsh_fail/os-release \
    PLASTICINE_SHELL_TTY=1 \
    scenario_path=$linux_chsh_fail/fake-bin \
    run_installer "$linux_chsh_fail" -y --shell \
    >"$linux_chsh_fail/stdout" 2>"$linux_chsh_fail/stderr"; then
    fail 'Denied chsh was treated as success.'
fi
scenario_path=''
expect_config "$linux_chsh_fail" 'denied chsh'
grep -Fq 'chsh failed' "$linux_chsh_fail/stderr"
grep -Fq 'chsh -s' "$linux_chsh_fail/fake-bin/calls"
linux_chsh_fail_before=$(find "$linux_chsh_fail/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
: > "$linux_chsh_fail/fake-bin/calls"
rm -f "$linux_chsh_fail/fake-bin/chsh-fails"
PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_chsh_fail/os-release \
    PLASTICINE_SHELL_TTY=1 \
    scenario_path=$linux_chsh_fail/fake-bin \
    run_installer "$linux_chsh_fail" -y --shell
scenario_path=''
linux_chsh_fail_after=$(find "$linux_chsh_fail/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
test "$linux_chsh_fail_before" = "$linux_chsh_fail_after"
grep -Fxq "chsh -s $linux_chsh_fail/fake-bin/zsh" "$linux_chsh_fail/fake-bin/calls"
test "$(grep -c . "$linux_chsh_fail/fake-bin/calls" | tr -d ' ')" = 1

# No-terminal chsh failure retains configuration and never fabricates input.
linux_chsh_tty=$test_root/linux-chsh-tty
mkdir -p "$linux_chsh_tty/home"
write_bootstrap_bin "$linux_chsh_tty/fake-bin"
write_antidote "$linux_chsh_tty/home"
printf '%s\n' '/bin/bash' > "$linux_chsh_tty/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_chsh_tty/os-release"
cp "$linux_chsh_tty/fake-bin/zsh.fixture" "$linux_chsh_tty/fake-bin/zsh"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_chsh_tty/os-release \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$linux_chsh_tty/fake-bin \
    run_installer "$linux_chsh_tty" -y --shell \
    >"$linux_chsh_tty/stdout" 2>"$linux_chsh_tty/stderr"; then
    fail 'chsh without a terminal was treated as success.'
fi
scenario_path=''
grep -Fq 'native terminal' "$linux_chsh_tty/stderr"
if grep -Fq 'chsh ' "$linux_chsh_tty/fake-bin/calls"; then
    fail 'chsh ran without a terminal.'
fi
expect_config "$linux_chsh_tty" 'no-terminal chsh'

# Successful chsh exit is verified against the native account database.
linux_chsh_lie=$test_root/linux-chsh-lie
mkdir -p "$linux_chsh_lie/home"
write_bootstrap_bin "$linux_chsh_lie/fake-bin"
write_antidote "$linux_chsh_lie/home"
printf '%s\n' '/bin/bash' > "$linux_chsh_lie/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_chsh_lie/os-release"
cp "$linux_chsh_lie/fake-bin/zsh.fixture" "$linux_chsh_lie/fake-bin/zsh"
: > "$linux_chsh_lie/fake-bin/chsh-lies"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_chsh_lie/os-release \
    PLASTICINE_SHELL_TTY=1 \
    scenario_path=$linux_chsh_lie/fake-bin \
    run_installer "$linux_chsh_lie" -y --shell \
    >"$linux_chsh_lie/stdout" 2>"$linux_chsh_lie/stderr"; then
    fail 'Unobserved chsh success was accepted.'
fi
scenario_path=''
grep -Fq 'did not update' "$linux_chsh_lie/stderr"
expect_config "$linux_chsh_lie" 'lying chsh'

# Official route failures prevent configuration and do not fall back.
for failure in apt-fails git-fails bundle-fails; do
    linux_fail=$test_root/linux-fail-$failure
    mkdir -p "$linux_fail/home"
    write_bootstrap_bin "$linux_fail/fake-bin"
    printf '%s\n' '/bin/bash' > "$linux_fail/fake-bin/login"
    printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_fail/os-release"
    : > "$linux_fail/fake-bin/$failure"
    if PLASTICINE_SHELL_OS=Linux \
        PLASTICINE_SHELL_ARCH=arm64 \
        PLASTICINE_SHELL_OS_RELEASE=$linux_fail/os-release \
        PLASTICINE_SHELL_HIDE_ZSH=1 \
        PLASTICINE_SHELL_APT_ZSH=$linux_fail/fake-bin/zsh \
        PLASTICINE_SHELL_TTY=1 \
        scenario_path=$linux_fail/fake-bin \
        run_installer "$linux_fail" -y --shell \
        >"$linux_fail/stdout" 2>"$linux_fail/stderr"; then
        fail "Route failure ($failure) was treated as success."
    fi
    scenario_path=''
    expect_no_config "$linux_fail" "$failure"
    if grep -Fq 'chsh ' "$linux_fail/fake-bin/calls"; then
        fail "$failure invoked chsh."
    fi
    if grep -Fq 'brew install' "$linux_fail/fake-bin/calls"; then
        fail "$failure fell back to Homebrew."
    fi
done

# Nonterminal APT uses sudo -n children only.
linux_nontty=$test_root/linux-nontty
mkdir -p "$linux_nontty/home"
write_bootstrap_bin "$linux_nontty/fake-bin"
write_antidote "$linux_nontty/home" missing-p10k
cp "$linux_nontty/fake-bin/zsh.fixture" "$linux_nontty/fake-bin/zsh"
printf '%s\n' "$linux_nontty/fake-bin/zsh" > "$linux_nontty/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_nontty/os-release"
rm -rf "$linux_nontty/home/.antidote" "$linux_nontty/home/.cache"
if ! PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_nontty/os-release \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_APT_ZSH=$linux_nontty/fake-bin/zsh \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$linux_nontty/fake-bin \
    run_installer "$linux_nontty" -y --shell \
    >"$linux_nontty/stdout" 2>"$linux_nontty/stderr"; then
    cat "$linux_nontty/stdout" >&2
    cat "$linux_nontty/stderr" >&2
    cat "$linux_nontty/fake-bin/calls" >&2
    fail 'nonterminal APT bootstrap failed'
fi
scenario_path=''
grep -Fq 'sudo -n apt-get update' "$linux_nontty/fake-bin/calls" || fail 'nonterminal APT did not use sudo -n update.'
grep -Fq 'sudo -n apt-get install -y --no-upgrade zsh' "$linux_nontty/fake-bin/calls" ||
    fail 'nonterminal APT did not use sudo -n install.'
expect_config "$linux_nontty" 'nonterminal APT'

# Destination validation precedes every installer effect.
linux_malformed=$test_root/linux-malformed
mkdir -p "$linux_malformed/home"
write_bootstrap_bin "$linux_malformed/fake-bin"
printf '%s\n' '/bin/bash' > "$linux_malformed/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_malformed/os-release"
printf '%s\n' '# >>> Plasticine shell >>>' > "$linux_malformed/home/.zshrc"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_malformed/os-release \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_APT_ZSH=$linux_malformed/fake-bin/zsh \
    PLASTICINE_SHELL_TTY=1 \
    scenario_path=$linux_malformed/fake-bin \
    run_installer "$linux_malformed" -y --shell \
    >"$linux_malformed/stdout" 2>"$linux_malformed/stderr"; then
    fail 'Malformed markers did not block bootstrap.'
fi
scenario_path=''
test ! -s "$linux_malformed/fake-bin/calls"
printf '%s\n' '# >>> Plasticine shell >>>' > "$linux_malformed/expected"
cmp -s "$linux_malformed/expected" "$linux_malformed/home/.zshrc"
test ! -e "$linux_malformed/home/.zsh_plugins.txt"

linux_fifo=$test_root/linux-fifo
mkdir -p "$linux_fifo/home"
write_bootstrap_bin "$linux_fifo/fake-bin"
printf '%s\n' '/bin/bash' > "$linux_fifo/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_fifo/os-release"
mkfifo "$linux_fifo/home/.p10k.zsh"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_fifo/os-release \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_APT_ZSH=$linux_fifo/fake-bin/zsh \
    PLASTICINE_SHELL_TTY=1 \
    scenario_path=$linux_fifo/fake-bin \
    run_installer "$linux_fifo" -y --shell \
    >"$linux_fifo/stdout" 2>"$linux_fifo/stderr"; then
    fail 'Non-regular p10k did not block bootstrap.'
fi
scenario_path=''
test ! -s "$linux_fifo/fake-bin/calls"
test -p "$linux_fifo/home/.p10k.zsh"

# Equivalent merged-usr Zsh paths skip chsh.
linux_merged=$test_root/linux-merged
mkdir -p "$linux_merged/home"
write_bootstrap_bin "$linux_merged/fake-bin"
write_antidote "$linux_merged/home"
printf '%s\n' '/usr/bin/zsh' > "$linux_merged/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_merged/os-release"
PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_merged/os-release \
    PLASTICINE_SHELL_ZSH=/bin/zsh \
    PLASTICINE_SHELL_TTY=1 \
    scenario_path=$linux_merged/fake-bin \
    run_installer "$linux_merged" -y --shell \
    >"$linux_merged/stdout" 2>"$linux_merged/stderr"
scenario_path=''
grep -Fq 'no chsh call' "$linux_merged/stdout"
if grep -Fq 'chsh ' "$linux_merged/fake-bin/calls"; then
    fail 'Equivalent merged-usr paths still invoked chsh.'
fi
expect_config "$linux_merged" 'merged-usr'

# Reviewed Debian/Ubuntu versions and architectures; others fail preflight.
for distro_spec in 'debian 13 arm64 0' 'ubuntu 24.04 aarch64 0' 'ubuntu 26.04 arm64 0' \
    'debian 12 arm64 1' 'ubuntu 22.04 x86_64 1' 'fedora 43 arm64 0' 'debian 13 mips 1'; do
    set -- $distro_spec
    linux_plat=$test_root/linux-plat-$1-$2-$3
    mkdir -p "$linux_plat/home"
    write_bootstrap_bin "$linux_plat/fake-bin"
    write_antidote "$linux_plat/home"
    cp "$linux_plat/fake-bin/zsh.fixture" "$linux_plat/fake-bin/zsh"
    printf '%s\n' "$linux_plat/fake-bin/zsh" > "$linux_plat/fake-bin/login"
    printf 'ID=%s\nVERSION_ID="%s"\n' "$1" "$2" > "$linux_plat/os-release"
    plat_status=0
    PLASTICINE_SHELL_OS=Linux \
        PLASTICINE_SHELL_ARCH=$3 \
        PLASTICINE_SHELL_OS_RELEASE=$linux_plat/os-release \
        PLASTICINE_SHELL_TTY=0 \
        scenario_path=$linux_plat/fake-bin \
        run_installer "$linux_plat" -y --shell \
        >"$linux_plat/stdout" 2>"$linux_plat/stderr" || plat_status=$?
    scenario_path=''
    if [ "$4" -eq 0 ]; then
        test "$plat_status" -eq 0 || fail "supported $1 $2 $3 failed."
        if [ "$2" = 26.04 ]; then
            grep -Fq best-effort "$linux_plat/stdout"
        fi
        test ! -s "$linux_plat/fake-bin/calls"
    else
        test "$plat_status" -ne 0 || fail "unsupported $1 $2 $3 was accepted."
        test ! -s "$linux_plat/fake-bin/calls"
        expect_no_config "$linux_plat" "$1 $2 $3"
    fi
done

# macOS missing Antidote uses Homebrew without sudo or a Linux clone.
# A failing PATH Zsh must not become the planned login shell.
macos_brew=$test_root/macos-brew
mkdir -p "$macos_brew/home"
write_bootstrap_bin "$macos_brew/fake-bin"
printf '%s\n' /bin/zsh > "$macos_brew/fake-bin/login"
cat > "$macos_brew/fake-bin/zsh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$macos_brew/fake-bin/zsh"
PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_SHELL_TTY=0 \
    PLASTICINE_TEST_LOGIN_SHELL=/bin/zsh \
    scenario_path=$macos_brew/fake-bin \
    run_installer "$macos_brew" -y --shell \
    >"$macos_brew/stdout" 2>"$macos_brew/stderr"
scenario_path=''
grep -Fq 'Zsh route: system' "$macos_brew/stdout"
grep -Fq 'Antidote route: brew' "$macos_brew/stdout"
grep -Fq 'brew install antidote' "$macos_brew/stdout"
grep -Fq 'administrator credentials' "$macos_brew/stdout"
grep -Fq 'brew install antidote' "$macos_brew/fake-bin/calls"
if grep -Fq sudo "$macos_brew/fake-bin/calls"; then
    fail 'macOS Homebrew used sudo.'
fi
if grep -Fq 'git clone' "$macos_brew/fake-bin/calls"; then
    fail 'macOS Homebrew fell back to git clone.'
fi
expect_config "$macos_brew" 'macOS Homebrew Antidote'

# Missing macOS Homebrew previews native privileges and bootstraps unprivileged.
macos_bootstrap=$test_root/macos-bootstrap
mkdir -p "$macos_bootstrap/home"
write_bootstrap_bin "$macos_bootstrap/fake-bin"
cp "$macos_bootstrap/fake-bin/zsh.fixture" "$macos_bootstrap/fake-bin/system-zsh"
printf '%s\n' "$macos_bootstrap/fake-bin/system-zsh" > "$macos_bootstrap/fake-bin/login"
# No brew on PATH: rename the fake brew so resolve misses it, then bootstrap copies it back.
mv "$macos_bootstrap/fake-bin/brew" "$macos_bootstrap/fake-bin/brew.available"
if PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_SHELL_HOMEBREW_ARM=$macos_bootstrap/fake-bin/brew \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_HIDE_BREW=1 \
    PLASTICINE_SHELL_SYSTEM_ZSH=$macos_bootstrap/fake-bin/system-zsh \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$macos_bootstrap/fake-bin \
    run_installer "$macos_bootstrap" -y --shell \
    >"$macos_bootstrap/stdout" 2>"$macos_bootstrap/stderr"; then
    fail 'Homebrew bootstrap without a terminal was treated as success.'
fi
scenario_path=''
if ! grep -Fq 'Homebrew missing' "$macos_bootstrap/stdout"; then
    cat "$macos_bootstrap/stdout" >&2
    cat "$macos_bootstrap/stderr" >&2
    fail 'brew-bootstrap preview missing Homebrew missing.'
fi
grep -Fq 'native terminal' "$macos_bootstrap/stdout" || fail 'brew-bootstrap preview missing native terminal.'
grep -Fq 'Homebrew itself may request administrator' "$macos_bootstrap/stdout" ||
    fail 'brew-bootstrap preview missing administrator disclosure.'
test ! -s "$macos_bootstrap/fake-bin/calls" || fail 'brew-bootstrap without a TTY still invoked installers.'
expect_no_config "$macos_bootstrap" 'brew-bootstrap without TTY'

PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_SHELL_HOMEBREW_ARM=$macos_bootstrap/fake-bin/brew \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_HIDE_BREW=1 \
    PLASTICINE_SHELL_SYSTEM_ZSH=$macos_bootstrap/fake-bin/system-zsh \
    PLASTICINE_SHELL_TTY=1 \
    NONINTERACTIVE=1 \
    CI=1 \
    scenario_path=$macos_bootstrap/fake-bin \
    run_installer "$macos_bootstrap" -y --shell \
    >"$macos_bootstrap/apply-stdout" 2>"$macos_bootstrap/apply-stderr"
scenario_path=''
macos_bootstrap_log=$(cat "$macos_bootstrap/fake-bin/calls")
printf '%s\n' "$macos_bootstrap_log" | grep -Fq 'curl official-homebrew'
printf '%s\n' "$macos_bootstrap_log" | grep -Fq 'bash official-homebrew unprivileged'
printf '%s\n' "$macos_bootstrap_log" | grep -Fq 'brew install antidote'
printf '%s\n' "$macos_bootstrap_log" | grep -Fq 'bundle romkatv/powerlevel10k kind:clone'
if grep -Fq sudo "$macos_bootstrap/fake-bin/calls"; then
    fail 'Homebrew bootstrap used sudo.'
fi
expect_config "$macos_bootstrap" 'macOS Homebrew bootstrap'
curl_at=$(printf '%s\n' "$macos_bootstrap_log" | grep -n 'curl official' | head -n1 | cut -d: -f1)
bash_at=$(printf '%s\n' "$macos_bootstrap_log" | grep -n 'bash official' | head -n1 | cut -d: -f1)
brew_at=$(printf '%s\n' "$macos_bootstrap_log" | grep -n 'brew install' | head -n1 | cut -d: -f1)
bundle_at=$(printf '%s\n' "$macos_bootstrap_log" | grep -n 'bundle ' | head -n1 | cut -d: -f1)
test "$curl_at" -lt "$bash_at"
test "$bash_at" -lt "$brew_at"
test "$brew_at" -lt "$bundle_at"

# Missing Git CLT is reported without launching a GUI or mutating the host.
macos_clt=$test_root/macos-clt
mkdir -p "$macos_clt/home"
write_bootstrap_bin "$macos_clt/fake-bin"
printf '%s\n' /bin/zsh > "$macos_clt/fake-bin/login"
cp "$macos_clt/fake-bin/zsh.fixture" "$macos_clt/fake-bin/zsh"
: > "$macos_clt/fake-bin/clt-fails"
if PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$macos_clt/fake-bin \
    run_installer "$macos_clt" -y --shell \
    >"$macos_clt/stdout" 2>"$macos_clt/stderr"; then
    fail 'Missing CLT was accepted.'
fi
scenario_path=''
grep -Fq 'Command Line Tools' "$macos_clt/stderr"
test ! -s "$macos_clt/fake-bin/calls"
expect_no_config "$macos_clt" 'missing CLT'

# Homebrew or plugin failure preserves ownership and prevents writes.
for failure in brew-fails bundle-fails; do
    macos_fail=$test_root/macos-fail-$failure
    mkdir -p "$macos_fail/home"
    write_bootstrap_bin "$macos_fail/fake-bin"
    printf '%s\n' /bin/zsh > "$macos_fail/fake-bin/login"
    cp "$macos_fail/fake-bin/zsh.fixture" "$macos_fail/fake-bin/zsh"
    : > "$macos_fail/fake-bin/$failure"
    if PLASTICINE_SHELL_OS=Darwin \
        PLASTICINE_SHELL_ARCH=arm64 \
        PLASTICINE_SHELL_MACOS_VERSION=14.0 \
        PLASTICINE_SHELL_TTY=0 \
        scenario_path=$macos_fail/fake-bin \
        run_installer "$macos_fail" -y --shell \
        >"$macos_fail/stdout" 2>"$macos_fail/stderr"; then
        fail "macOS route failure ($failure) was treated as success."
    fi
    scenario_path=''
    expect_no_config "$macos_fail" "macOS $failure"
    if grep -Fq 'git clone' "$macos_fail/fake-bin/calls"; then
        fail "$failure fell back to git clone."
    fi
    if grep -Fq sudo "$macos_fail/fake-bin/calls"; then
        fail "$failure used sudo."
    fi
done

# macOS floors, Intel/newer best-effort labels, and unknown platforms.
for mac_spec in '13.0 arm64 1' '14.0 x86_64 0' '26.0 arm64 0'; do
    set -- $mac_spec
    macos_plat=$test_root/macos-plat-$1-$2
    mkdir -p "$macos_plat/home"
    write_bootstrap_bin "$macos_plat/fake-bin"
    write_antidote "$macos_plat/home"
    mkdir -p "$macos_plat/fake-bin/prefix/share/antidote"
    cp "$macos_plat/home/.antidote/antidote.zsh" "$macos_plat/fake-bin/prefix/share/antidote/antidote.zsh"
    printf '%s\n' /bin/zsh > "$macos_plat/fake-bin/login"
    plat_status=0
    PLASTICINE_SHELL_OS=Darwin \
        PLASTICINE_SHELL_ARCH=$2 \
        PLASTICINE_SHELL_MACOS_VERSION=$1 \
        PLASTICINE_SHELL_TTY=0 \
        PLASTICINE_TEST_LOGIN_SHELL=/bin/zsh \
        scenario_path=$macos_plat/fake-bin \
        run_installer "$macos_plat" -y --shell \
        >"$macos_plat/stdout" 2>"$macos_plat/stderr" || plat_status=$?
    scenario_path=''
    if [ "$3" -eq 0 ]; then
        test "$plat_status" -eq 0 || fail "macOS $1 $2 failed."
        grep -Fq best-effort "$macos_plat/stdout"
    else
        test "$plat_status" -ne 0 || fail "macOS $1 $2 was accepted."
        expect_no_config "$macos_plat" "macOS $1 $2"
    fi
done

# Unhealthy existing Git is not replaced by another owner.
linux_git_unhealthy=$test_root/linux-git-unhealthy
mkdir -p "$linux_git_unhealthy/home"
write_bootstrap_bin "$linux_git_unhealthy/fake-bin"
write_antidote "$linux_git_unhealthy/home" missing-p10k
cp "$linux_git_unhealthy/fake-bin/zsh.fixture" "$linux_git_unhealthy/fake-bin/zsh"
printf '%s\n' "$linux_git_unhealthy/fake-bin/zsh" > "$linux_git_unhealthy/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_git_unhealthy/os-release"
: > "$linux_git_unhealthy/fake-bin/git-unhealthy"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_git_unhealthy/os-release \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$linux_git_unhealthy/fake-bin \
    run_installer "$linux_git_unhealthy" -y --shell \
    >"$linux_git_unhealthy/stdout" 2>"$linux_git_unhealthy/stderr"; then
    fail 'Unhealthy Git was replaced.'
fi
scenario_path=''
grep -Fq Git "$linux_git_unhealthy/stderr"
test ! -s "$linux_git_unhealthy/fake-bin/calls"
expect_no_config "$linux_git_unhealthy" 'unhealthy Git'

# APT Zsh with healthy Antidote/p10k must not require Git.
linux_apt_no_git=$test_root/linux-apt-no-git
mkdir -p "$linux_apt_no_git/home"
write_bootstrap_bin "$linux_apt_no_git/fake-bin"
write_antidote "$linux_apt_no_git/home"
printf '%s\n' "$linux_apt_no_git/fake-bin/zsh" > "$linux_apt_no_git/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_apt_no_git/os-release"
: > "$linux_apt_no_git/fake-bin/git-unhealthy"
if ! PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_apt_no_git/os-release \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_APT_ZSH=$linux_apt_no_git/fake-bin/zsh \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$linux_apt_no_git/fake-bin \
    run_installer "$linux_apt_no_git" -y --shell \
    >"$linux_apt_no_git/stdout" 2>"$linux_apt_no_git/stderr"; then
    cat "$linux_apt_no_git/stdout" >&2
    cat "$linux_apt_no_git/stderr" >&2
    fail 'APT Zsh with existing p10k failed because of unrelated Git.'
fi
scenario_path=''
grep -Fq 'sudo -n apt-get install -y --no-upgrade zsh' "$linux_apt_no_git/fake-bin/calls" ||
    fail 'APT Zsh with existing p10k did not install zsh.'
if grep -Fq git "$linux_apt_no_git/fake-bin/calls"; then
    fail 'APT Zsh with existing p10k still mutated Git.'
fi
expect_config "$linux_apt_no_git" 'APT Zsh without Git'

# Unhealthy Homebrew is left untouched.
macos_brew_unhealthy=$test_root/macos-brew-unhealthy
mkdir -p "$macos_brew_unhealthy/home"
write_bootstrap_bin "$macos_brew_unhealthy/fake-bin"
cp "$macos_brew_unhealthy/fake-bin/zsh.fixture" "$macos_brew_unhealthy/fake-bin/zsh"
printf '%s\n' "$macos_brew_unhealthy/fake-bin/zsh" > "$macos_brew_unhealthy/fake-bin/login"
: > "$macos_brew_unhealthy/fake-bin/brew-unhealthy"
if PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$macos_brew_unhealthy/fake-bin \
    run_installer "$macos_brew_unhealthy" -y --shell \
    >"$macos_brew_unhealthy/stdout" 2>"$macos_brew_unhealthy/stderr"; then
    fail 'Unhealthy Homebrew was replaced.'
fi
scenario_path=''
grep -Fq Homebrew "$macos_brew_unhealthy/stderr"
test ! -s "$macos_brew_unhealthy/fake-bin/calls"
expect_no_config "$macos_brew_unhealthy" 'unhealthy Homebrew'

# Existing broken Powerlevel10k is left untouched.
linux_p10k_unhealthy=$test_root/linux-p10k-unhealthy
mkdir -p "$linux_p10k_unhealthy/home"
write_bootstrap_bin "$linux_p10k_unhealthy/fake-bin"
write_antidote "$linux_p10k_unhealthy/home"
printf '%s\n' 'if ; broken' > "$linux_p10k_unhealthy/home/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme"
cp "$linux_p10k_unhealthy/fake-bin/zsh.fixture" "$linux_p10k_unhealthy/fake-bin/zsh"
printf '%s\n' "$linux_p10k_unhealthy/fake-bin/zsh" > "$linux_p10k_unhealthy/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_p10k_unhealthy/os-release"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_p10k_unhealthy/os-release \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$linux_p10k_unhealthy/fake-bin \
    run_installer "$linux_p10k_unhealthy" -y --shell \
    >"$linux_p10k_unhealthy/stdout" 2>"$linux_p10k_unhealthy/stderr"; then
    fail 'Unhealthy Powerlevel10k was replaced.'
fi
scenario_path=''
grep -Fq Powerlevel10k "$linux_p10k_unhealthy/stderr"
test ! -s "$linux_p10k_unhealthy/fake-bin/calls"
expect_no_config "$linux_p10k_unhealthy" 'unhealthy Powerlevel10k'

# Rerun after plugin failure resumes without reinstalling healthy tools.
linux_p10k_retry=$test_root/linux-p10k-retry
mkdir -p "$linux_p10k_retry/home"
write_bootstrap_bin "$linux_p10k_retry/fake-bin"
write_antidote "$linux_p10k_retry/home" missing-p10k
cp "$linux_p10k_retry/fake-bin/zsh.fixture" "$linux_p10k_retry/fake-bin/zsh"
printf '%s\n' "$linux_p10k_retry/fake-bin/zsh" > "$linux_p10k_retry/fake-bin/login"
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_p10k_retry/os-release"
: > "$linux_p10k_retry/fake-bin/bundle-fails"
if PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_p10k_retry/os-release \
    PLASTICINE_SHELL_TTY=0 \
    PLASTICINE_TEST_BUNDLE_FAILS=$linux_p10k_retry/fake-bin/bundle-fails \
    scenario_path=$linux_p10k_retry/fake-bin \
    run_installer "$linux_p10k_retry" -y --shell \
    >"$linux_p10k_retry/stdout" 2>"$linux_p10k_retry/stderr"; then
    fail 'Failed plugin bootstrap was treated as success.'
fi
scenario_path=''
expect_no_config "$linux_p10k_retry" 'failed plugin bootstrap'
rm -f "$linux_p10k_retry/fake-bin/bundle-fails"
: > "$linux_p10k_retry/fake-bin/calls"
PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_p10k_retry/os-release \
    PLASTICINE_SHELL_TTY=0 \
    PLASTICINE_TEST_CALLS=$linux_p10k_retry/fake-bin/calls \
    scenario_path=$linux_p10k_retry/fake-bin \
    run_installer "$linux_p10k_retry" -y --shell
scenario_path=''
grep -Fq 'bundle romkatv/powerlevel10k kind:clone' "$linux_p10k_retry/fake-bin/calls"
if grep -Fq 'apt-get ' "$linux_p10k_retry/fake-bin/calls"; then
    fail 'plugin retry reinstalled APT packages.'
fi
if grep -Fq 'git clone' "$linux_p10k_retry/fake-bin/calls"; then
    fail 'plugin retry recloned Antidote.'
fi
expect_config "$linux_p10k_retry" 'plugin retry'

# Official Homebrew download failure has no shell execution or configuration.
macos_curl_fail=$test_root/macos-curl-fail
mkdir -p "$macos_curl_fail/home"
write_bootstrap_bin "$macos_curl_fail/fake-bin"
printf '%s\n' /bin/zsh > "$macos_curl_fail/fake-bin/login"
cp "$macos_curl_fail/fake-bin/zsh.fixture" "$macos_curl_fail/fake-bin/system-zsh"
mv "$macos_curl_fail/fake-bin/brew" "$macos_curl_fail/fake-bin/brew.available"
: > "$macos_curl_fail/fake-bin/curl-fails"
if PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_SHELL_HOMEBREW_ARM=$macos_curl_fail/fake-bin/brew \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_HIDE_BREW=1 \
    PLASTICINE_SHELL_SYSTEM_ZSH=$macos_curl_fail/fake-bin/system-zsh \
    PLASTICINE_SHELL_TTY=1 \
    scenario_path=$macos_curl_fail/fake-bin \
    run_installer "$macos_curl_fail" -y --shell \
    >"$macos_curl_fail/stdout" 2>"$macos_curl_fail/stderr"; then
    fail 'Failed Homebrew download was treated as success.'
fi
scenario_path=''
test "$(cat "$macos_curl_fail/fake-bin/calls")" = 'curl official-homebrew'
expect_no_config "$macos_curl_fail" 'Homebrew download failure'

# Absent or unhealthy expected system Zsh fails with guidance.
macos_system_zsh=$test_root/macos-system-zsh
mkdir -p "$macos_system_zsh/home"
write_bootstrap_bin "$macos_system_zsh/fake-bin"
write_antidote "$macos_system_zsh/home"
printf '%s\n' /bin/zsh > "$macos_system_zsh/fake-bin/login"
if PLASTICINE_SHELL_OS=Darwin \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_MACOS_VERSION=14.0 \
    PLASTICINE_SHELL_HIDE_ZSH=1 \
    PLASTICINE_SHELL_SYSTEM_ZSH=$macos_system_zsh/missing-zsh \
    PLASTICINE_SHELL_TTY=0 \
    scenario_path=$macos_system_zsh/fake-bin \
    run_installer "$macos_system_zsh" -y --shell \
    >"$macos_system_zsh/stdout" 2>"$macos_system_zsh/stderr"; then
    fail 'Missing system Zsh was accepted.'
fi
scenario_path=''
grep -Fq Zsh "$macos_system_zsh/stderr"
expect_no_config "$macos_system_zsh" 'missing system Zsh'

printf '%s\n' 'shell tests passed'
