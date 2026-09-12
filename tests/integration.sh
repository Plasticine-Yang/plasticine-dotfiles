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

test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-dotfiles-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

write_config() {
    config_path=$1
    key_path=$2
    source_fingerprint=$3
    replace_fingerprint=$4
    cat > "$config_path" <<EOF
[data]
tools = ["github-ssh"]
githubSSHKeyPath = "$key_path"
githubSSHKeyFingerprint = "$source_fingerprint"
githubSSHReplaceFingerprint = "$replace_fingerprint"
githubSSHTest = false
EOF
}

apply() {
    scenario_dir=$1
    shift
    "$chezmoi_bin" \
        -S "$repo_dir" \
        -D "$scenario_dir/home" \
        -c "$scenario_dir/chezmoi.toml" \
        --persistent-state "$scenario_dir/state.boltdb" \
        apply --no-tty "$@"
}

success_dir=$test_root/success
mkdir -p "$success_dir/home/.ssh"
chmod 700 "$success_dir/home/.ssh"
mkdir -p "$success_dir/key dir"
source_key=$(printf "%s/key dir/key's-ed25519" "$success_dir")
ssh-keygen -q -t ed25519 -N '' -C plasticine-success -f "$source_key"
source_fingerprint=$(ssh-keygen -lf "$source_key" | awk '{ print $2 }')
write_config "$success_dir/chezmoi.toml" "$source_key" "$source_fingerprint" ''
printf 'Host example.com\n    User existing-user\n' > "$success_dir/home/.ssh/config"
cp "$success_dir/home/.ssh/config" "$success_dir/config-before"

apply "$success_dir" --dry-run
test ! -e "$success_dir/home/.ssh/id_github"
test ! -e "$success_dir/home/.ssh/config.d/00-plasticine-github.conf"
apply "$success_dir"
cmp -s "$source_key" "$success_dir/home/.ssh/id_github"
cmp -s "$success_dir/config-before" "$success_dir/home/.ssh/config.plasticine-backup-before-managed"
test "$(grep -Fc '# BEGIN plasticine-dotfiles github-ssh' "$success_dir/home/.ssh/config")" -eq 1
apply "$success_dir"
test "$(grep -Fc '# BEGIN plasticine-dotfiles github-ssh' "$success_dir/home/.ssh/config")" -eq 1
test "$(find "$success_dir/home/.ssh" -name 'config.plasticine-backup-*' | wc -l | tr -d ' ')" -eq 1
grep -Fq 'Host example.com' "$success_dir/home/.ssh/config"
effective_identity=$(ssh -G -F "$success_dir/home/.ssh/config.d/00-plasticine-github.conf" github.com 2>/dev/null | awk '$1 == "identityfile" { print $2 }')
expected_identity=$(printf '\176/.ssh/id_github')
test "$effective_identity" = "$expected_identity"
for private_path in \
    "$success_dir/home/.ssh" \
    "$success_dir/home/.ssh/config.d" \
    "$success_dir/home/.ssh/config" \
    "$success_dir/home/.ssh/config.d/00-plasticine-github.conf" \
    "$success_dir/home/.ssh/id_github"; do
    if [ "$(uname -s)" = Darwin ]; then
        mode=$(stat -f '%Lp' "$private_path")
    else
        mode=$(stat -c '%a' "$private_path")
    fi
    case $private_path in
        */.ssh|*/config.d) test "$mode" = 700 ;;
        *) test "$mode" = 600 ;;
    esac
done
rm "$source_key" "$source_key.pub"
apply "$success_dir"

conflict_dir=$test_root/conflict
mkdir -p "$conflict_dir/home/.ssh"
conflict_key=$conflict_dir/source-key
ssh-keygen -q -t ed25519 -N '' -C plasticine-conflict -f "$conflict_key"
conflict_fingerprint=$(ssh-keygen -lf "$conflict_key" | awk '{ print $2 }')
write_config "$conflict_dir/chezmoi.toml" "$conflict_key" "$conflict_fingerprint" ''
printf 'Host github.com\n    User git\n    IdentityFile ~/.ssh/id_existing\n' > "$conflict_dir/home/.ssh/config"
cp "$conflict_dir/home/.ssh/config" "$conflict_dir/config-before"
if apply "$conflict_dir" >/dev/null 2>&1; then
    printf '%s\n' '冲突配置未被拒绝。' >&2
    exit 1
fi
cmp -s "$conflict_dir/config-before" "$conflict_dir/home/.ssh/config"
test ! -e "$conflict_dir/home/.ssh/id_github"
test ! -e "$conflict_dir/home/.ssh/config.d/00-plasticine-github.conf"
test ! -e "$conflict_dir/home/.ssh/config.plasticine-backup-before-managed"

replace_dir=$test_root/replace
mkdir -p "$replace_dir/home/.ssh"
ssh-keygen -q -t ed25519 -N '' -C plasticine-old -f "$replace_dir/home/.ssh/id_github"
replace_key=$replace_dir/source-key
ssh-keygen -q -t ed25519 -N '' -C plasticine-new -f "$replace_key"
old_fingerprint=$(ssh-keygen -lf "$replace_dir/home/.ssh/id_github" | awk '{ print $2 }')
replace_fingerprint=$(ssh-keygen -lf "$replace_key" | awk '{ print $2 }')
write_config "$replace_dir/chezmoi.toml" "$replace_key" "$replace_fingerprint" "$old_fingerprint"
apply "$replace_dir"
cmp -s "$replace_key" "$replace_dir/home/.ssh/id_github"
backup_key=$(find "$replace_dir/home/.ssh" -name 'id_github.plasticine-backup-*')
test "$(ssh-keygen -lf "$backup_key" | awk '{ print $2 }')" = "$old_fingerprint"

skip_dir=$test_root/skip
mkdir -p "$skip_dir/home/.ssh"
printf 'preserve-me\n' > "$skip_dir/home/.ssh/config"
printf 'preserve-shell\n' > "$skip_dir/home/.zshrc"
cat > "$skip_dir/chezmoi.toml" <<'EOF'
[data]
tools = []
githubSSHKeyPath = ""
githubSSHKeyFingerprint = ""
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
apply "$skip_dir"
test "$(cat "$skip_dir/home/.ssh/config")" = preserve-me
test ! -e "$skip_dir/home/.ssh/id_github"
test ! -e "$skip_dir/home/.ssh/config.d"
test "$(cat "$skip_dir/home/.zshrc")" = preserve-shell
test ! -e "$skip_dir/home/.zsh_plugins.txt"
test ! -e "$skip_dir/home/.p10k.zsh"
test ! -e "$skip_dir/home/.plasticine"

shell_dir=$test_root/shell
mkdir -p "$shell_dir/home/.antidote"
cat > "$shell_dir/home/.antidote/antidote.zsh" <<'EOF'
antidote() {
    case $1 in
        --version)
            print -r -- 'integration test antidote'
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
EOF
cat > "$shell_dir/chezmoi.toml" <<'EOF'
[data]
tools = ["shell"]
githubSSHKeyPath = ""
githubSSHKeyFingerprint = ""
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
apply "$shell_dir"
cat > "$shell_dir/expected-block" <<'EOF'
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
cmp -s "$shell_dir/expected-block" "$shell_dir/home/.zshrc"
cmp -s "$repo_dir/dot_zsh_plugins.txt" "$shell_dir/home/.zsh_plugins.txt"
cmp -s "$repo_dir/dot_p10k.zsh" "$shell_dir/home/.p10k.zsh"
cmp -s "$repo_dir/dot_plasticine/zsh/shared.zsh" "$shell_dir/home/.plasticine/zsh/shared.zsh"
apply "$shell_dir"

malformed_dir=$test_root/malformed
mkdir -p "$malformed_dir/home/.antidote"
cp "$shell_dir/home/.antidote/antidote.zsh" "$malformed_dir/home/.antidote/antidote.zsh"
cp "$shell_dir/chezmoi.toml" "$malformed_dir/chezmoi.toml"
cat "$shell_dir/expected-block" "$shell_dir/expected-block" > "$malformed_dir/home/.zshrc"
cp "$malformed_dir/home/.zshrc" "$malformed_dir/before"
if apply "$malformed_dir" >/dev/null 2>&1; then
    printf '%s\n' '损坏的 shell 区块未被拒绝。' >&2
    exit 1
fi
cmp -s "$malformed_dir/before" "$malformed_dir/home/.zshrc"
test ! -e "$malformed_dir/home/.zsh_plugins.txt"

combined_malformed_dir=$test_root/combined-malformed
mkdir -p "$combined_malformed_dir/home/.antidote" "$combined_malformed_dir/home/.ssh"
cp "$shell_dir/home/.antidote/antidote.zsh" "$combined_malformed_dir/home/.antidote/antidote.zsh"
cat > "$combined_malformed_dir/chezmoi.toml" <<EOF
[data]
tools = ["github-ssh","shell"]
githubSSHKeyPath = "$replace_key"
githubSSHKeyFingerprint = "$replace_fingerprint"
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
cat "$shell_dir/expected-block" "$shell_dir/expected-block" > "$combined_malformed_dir/home/.zshrc"
cp "$combined_malformed_dir/home/.zshrc" "$combined_malformed_dir/before"
if apply "$combined_malformed_dir" >/dev/null 2>&1; then
    printf '%s\n' '组合选择下损坏的 shell 区块未被拒绝。' >&2
    exit 1
fi
cmp -s "$combined_malformed_dir/before" "$combined_malformed_dir/home/.zshrc"
test ! -e "$combined_malformed_dir/home/.ssh/id_github"
test ! -e "$combined_malformed_dir/home/.ssh/config.d"

lint_dir=$test_root/lint
mkdir -p "$lint_dir/home"
cp "$replace_dir/chezmoi.toml" "$lint_dir/chezmoi.toml"
cat > "$lint_dir/shell-chezmoi.toml" <<'EOF'
[data]
tools = ["shell"]
githubSSHKeyPath = ""
githubSSHKeyFingerprint = ""
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
for source_script in "$repo_dir"/.chezmoiscripts/*.tmpl; do
    rendered_script=$lint_dir/$(basename "${source_script%.tmpl}")
    for config_file in "$lint_dir/chezmoi.toml" "$lint_dir/shell-chezmoi.toml"; do
        "$chezmoi_bin" \
            -S "$repo_dir" \
            -D "$lint_dir/home" \
            -c "$config_file" \
            execute-template < "$source_script" > "$rendered_script"
        if grep -q '[^[:space:]]' "$rendered_script"; then
            /bin/sh -n "$rendered_script"
            if command -v shellcheck >/dev/null 2>&1; then
                shellcheck "$rendered_script"
            fi
        fi
    done
done
"$chezmoi_bin" \
    -S "$repo_dir" \
    -D "$lint_dir/home" \
    -c "$lint_dir/shell-chezmoi.toml" \
    execute-template < "$repo_dir/modify_dot_zshrc.tmpl" > "$lint_dir/modify_dot_zshrc"
grep -q '[^[:space:]]' "$lint_dir/modify_dot_zshrc"
/bin/sh -n "$lint_dir/modify_dot_zshrc"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$lint_dir/modify_dot_zshrc"
fi
/bin/sh -n "$repo_dir/private_dot_ssh/modify_private_config"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$repo_dir/private_dot_ssh/modify_private_config"
fi
if command -v zsh >/dev/null 2>&1; then
    zsh -n "$repo_dir/dot_plasticine/zsh/shared.zsh"
    zsh -n "$repo_dir/dot_p10k.zsh"
fi

printf '%s\n' 'integration tests passed'
