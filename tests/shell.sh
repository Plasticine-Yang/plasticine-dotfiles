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

scenario_path=''
run_installer() {
    scenario_dir=$1
    shift
    PATH=${scenario_path:-$PATH} \
    PLASTICINE_CHEZMOI_BIN=$chezmoi_bin \
    PLASTICINE_DOTFILES_REPO_URL=$origin_repo \
    PLASTICINE_CHEZMOI_SOURCE_DIR=$scenario_dir/data/chezmoi \
    PLASTICINE_CHEZMOI_CONFIG_FILE=$scenario_dir/config/chezmoi.toml \
    PLASTICINE_CHEZMOI_STATE_FILE=$scenario_dir/config/chezmoistate.boltdb \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario_dir/home \
        "$repo_dir/install.sh" "$@"
}

write_antidote() {
    antidote_home=$1
    mkdir -p "$antidote_home/.antidote"
    cat > "$antidote_home/.antidote/antidote.zsh" <<'EOF'
antidote() {
    case $1 in
        --version)
            print -r -- 'plasticine shell test antidote'
            return 0
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
scenario_path="$empty_dir/fake-bin:$PATH" run_installer "$empty_dir" -y
scenario_path=''
grep -Fq 'tools = []' "$empty_dir/config/chezmoi.toml"
test ! -e "$probe_marker"
test ! -e "$empty_dir/home/.zshrc"
test ! -e "$empty_dir/home/.zsh_plugins.txt"
test ! -e "$empty_dir/home/.p10k.zsh"
test ! -e "$empty_dir/home/.plasticine"

# An existing healthy Zsh and Antidote are enough for the configuration seam.
shell_dir=$test_root/shell-only
mkdir -p "$shell_dir/home"
write_antidote "$shell_dir/home"
run_installer "$shell_dir" -y --shell
grep -Fq 'tools = ["shell"]' "$shell_dir/config/chezmoi.toml"
cmp -s "$block_file" "$shell_dir/home/.zshrc"
cmp -s "$repo_dir/dot_zsh_plugins.txt" "$shell_dir/home/.zsh_plugins.txt"
cmp -s "$repo_dir/dot_p10k.zsh" "$shell_dir/home/.p10k.zsh"
cmp -s "$repo_dir/dot_plasticine/zsh/shared.zsh" "$shell_dir/home/.plasticine/zsh/shared.zsh"
for target in .zshrc .zsh_plugins.txt .p10k.zsh .plasticine/zsh/shared.zsh; do
    test "$(file_mode "$shell_dir/home/$target")" = 644
done
test ! -e "$shell_dir/home/.plasticine/backups"

# shell and github-ssh compose into one unordered selection set.
combined_dir=$test_root/combined
mkdir -p "$combined_dir/home" "$combined_dir/key-dir"
write_antidote "$combined_dir/home"
combined_key=$combined_dir/key-dir/id_ed25519
ssh-keygen -q -t ed25519 -N '' -C shell-test -f "$combined_key"
run_installer "$combined_dir" -y --shell --github-ssh --github-ssh-key "$combined_key"
grep -Fq 'tools = ["github-ssh","shell"]' "$combined_dir/config/chezmoi.toml"
cmp -s "$combined_key" "$combined_dir/home/.ssh/id_github"
test -f "$combined_dir/home/.ssh/config.d/00-plasticine-github.conf"
cmp -s "$block_file" "$combined_dir/home/.zshrc"
cmp -s "$repo_dir/dot_zsh_plugins.txt" "$combined_dir/home/.zsh_plugins.txt"

# Missing or unhealthy prerequisites fail before any shell target changes.
missing_antidote_dir=$test_root/missing-antidote
mkdir -p "$missing_antidote_dir/home" "$missing_antidote_dir/fake-bin"
cat > "$missing_antidote_dir/fake-bin/brew" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$missing_antidote_dir/fake-bin/brew"
if scenario_path="$missing_antidote_dir/fake-bin:$PATH" \
    run_installer "$missing_antidote_dir" -y --shell \
    >"$missing_antidote_dir/stdout" 2>"$missing_antidote_dir/stderr"; then
    fail 'Missing Antidote was not rejected.'
fi
scenario_path=''
grep -Fq 'Antidote' "$missing_antidote_dir/stderr"
test ! -e "$missing_antidote_dir/home/.zshrc"
test ! -e "$missing_antidote_dir/home/.plasticine"

unhealthy_antidote_dir=$test_root/unhealthy-antidote
mkdir -p "$unhealthy_antidote_dir/home/.antidote"
cat > "$unhealthy_antidote_dir/home/.antidote/antidote.zsh" <<'EOF'
antidote() {
    return 1
}
EOF
if run_installer "$unhealthy_antidote_dir" -y --shell \
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
if scenario_path="$unhealthy_zsh_dir/fake-bin:$PATH" \
    run_installer "$unhealthy_zsh_dir" -y --shell \
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
run_installer "$preserve_dir" -y --shell
cat "$block_file" > "$preserve_dir/expected"
printf '# Owner\015\012\303\251\000\377\011tail' >> "$preserve_dir/expected"
cmp -s "$preserve_dir/expected" "$preserve_dir/home/.zshrc"

# A valid existing block is replaced in place and backed up.
replace_dir=$test_root/replace
mkdir -p "$replace_dir/home"
write_antidote "$replace_dir/home"
printf 'pre\015\012# >>> Plasticine shell >>>\012old body\012# <<< Plasticine shell <<<\012suf\000\377' \
    > "$replace_dir/home/.zshrc"
cp "$replace_dir/home/.zshrc" "$replace_dir/before"
chmod 640 "$replace_dir/home/.zshrc"
run_installer "$replace_dir" -y --shell
printf 'pre\015\012' > "$replace_dir/expected"
cat "$block_file" >> "$replace_dir/expected"
printf 'suf\000\377' >> "$replace_dir/expected"
cmp -s "$replace_dir/expected" "$replace_dir/home/.zshrc"
test "$(file_mode "$replace_dir/home/.zshrc")" = 640
backup_file=$(find "$replace_dir/home/.plasticine/backups/shell" -name '.zshrc.plasticine-backup-*')
test -n "$backup_file"
cmp -s "$replace_dir/before" "$backup_file"
test "$(file_mode "$backup_file")" = 600

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
    if run_installer "$malformed_dir" -y --shell \
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
        if run_installer "$unsafe_dir" -y --shell \
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
if run_installer "$symlinked_parent_dir" -y --shell \
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
run_installer "$rerun_dir" -y --shell
test "$(file_mode "$rerun_dir/home/.zshrc")" = 640
test "$(file_mode "$rerun_dir/home/.zsh_plugins.txt")" = 600
backup_count=$(find "$rerun_dir/home/.plasticine/backups/shell" -type f | wc -l | tr -d ' ')
test "$backup_count" -eq 2
before=$(find "$rerun_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
run_installer "$rerun_dir" -y --shell
after=$(find "$rerun_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
test "$before" = "$after"
test "$(file_mode "$rerun_dir/home/.zshrc")" = 640
test "$(file_mode "$rerun_dir/home/.zsh_plugins.txt")" = 600
backup_count=$(find "$rerun_dir/home/.plasticine/backups/shell" -type f | wc -l | tr -d ' ')
test "$backup_count" -eq 2

printf '%s\n' 'shell tests passed'
