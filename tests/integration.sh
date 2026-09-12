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

protect_bin=$test_root/protect-bin
mkdir -p "$protect_bin"
cat > "$protect_bin/chsh" <<'EOF'
#!/bin/sh
printf '%s\n' 'plasticine tests: host chsh blocked' >&2
exit 99
EOF
cat > "$protect_bin/dscl" <<'EOF'
#!/bin/sh
login=$(command -v zsh 2>/dev/null || true)
[ -n "$login" ] || login=/bin/zsh
printf 'UserShell: %s\n' "$login"
EOF
cat > "$protect_bin/getent" <<'EOF'
#!/bin/sh
[ "${1:-}" = passwd ] || exit 99
login=$(command -v zsh 2>/dev/null || true)
[ -n "$login" ] || login=/bin/zsh
printf 'owner:x:%s:%s:Owner:%s:%s\n' "$(id -u)" "$(id -u)" "${HOME:-/tmp}" "$login"
EOF
cat > "$protect_bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' 'plasticine tests: host sudo blocked' >&2
exit 99
EOF
cat > "$protect_bin/lazygit" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] || exit 99
printf '%s\n' 'lazygit version integration-fixture'
EOF
chmod +x "$protect_bin"/*

linux_os_release=$test_root/os-release
printf '%s\n' 'ID=debian' 'VERSION_ID=13' > "$linux_os_release"

write_antidote() {
    mkdir -p "$1/.antidote"
    mkdir -p "$1/.cache/antidote/github.com/romkatv/powerlevel10k"
    printf '%s\n' ':' > "$1/.cache/antidote/github.com/romkatv/powerlevel10k/powerlevel10k.zsh-theme"
    cat > "$1/.antidote/antidote.zsh" <<'EOF'
antidote() {
    case $1 in
        --version)
            print -r -- 'integration test antidote'
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

# Every chezmoi invocation for a scenario shares the same source, destination,
# config, state and platform seams.
chezmoi_scenario() {
    scenario_dir=$1
    shift
    PATH=$protect_bin:$PATH \
    PLASTICINE_CHEZMOI_DEST_DIR=$scenario_dir/home \
    PLASTICINE_SHELL_OS=Linux \
    PLASTICINE_SHELL_ARCH=arm64 \
    PLASTICINE_SHELL_OS_RELEASE=$linux_os_release \
        "$chezmoi_bin" \
        -S "$repo_dir" \
        -D "$scenario_dir/home" \
        -c "$scenario_dir/chezmoi.toml" \
        --persistent-state "$scenario_dir/state.boltdb" \
        "$@"
}

apply() {
    scenario_dir=$1
    shift
    chezmoi_scenario "$scenario_dir" apply --no-tty "$@"
}

# The same preview the installer shows before its final confirmation. Chezmoi
# reports `run_` scripts as pending on every invocation, so callers that care
# about destination convergence exclude them explicitly.
preview() {
    scenario_dir=$1
    shift
    chezmoi_scenario "$scenario_dir" diff --no-pager "$@"
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
mkdir -p "$shell_dir/home"
write_antidote "$shell_dir/home"
cat > "$shell_dir/chezmoi.toml" <<'EOF'
[data]
tools = ["shell"]
githubSSHKeyPath = ""
githubSSHKeyFingerprint = ""
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
# The preview covers the shell changes before anything is written, and a dry
# apply writes nothing at all.
preview "$shell_dir" > "$shell_dir/preview"
for expected_preview in .zshrc .zsh_plugins.txt .p10k.zsh .plasticine/zsh/shared.zsh; do
    grep -Fq "$expected_preview" "$shell_dir/preview" ||
        { cat "$shell_dir/preview" >&2; printf '%s\n' "shell 预览未包含 $expected_preview。" >&2; exit 1; }
done
apply "$shell_dir" --dry-run
test ! -e "$shell_dir/home/.zshrc"
test ! -e "$shell_dir/home/.zsh_plugins.txt"
test ! -e "$shell_dir/home/.p10k.zsh"
test ! -e "$shell_dir/home/.plasticine"
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
# A satisfied destination stays converged, including under a dry rerun.
shell_before=$(find "$shell_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
preview_output=$(preview "$shell_dir" --exclude=scripts)
if [ -n "$(printf '%s' "$preview_output" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$preview_output" >&2
    printf '%s\n' '已满足的 shell 目标仍报告待应用的变更。' >&2
    exit 1
fi
apply "$shell_dir" --dry-run
shell_after=$(find "$shell_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }')
test "$shell_before" = "$shell_after"
test ! -e "$shell_dir/home/.plasticine/backups"

# shell and github-ssh compose without either feature overwriting the other.
combined_dir=$test_root/combined
mkdir -p "$combined_dir/home/.ssh"
chmod 700 "$combined_dir/home/.ssh"
write_antidote "$combined_dir/home"
combined_key=$combined_dir/combined-key
ssh-keygen -q -t ed25519 -N '' -C plasticine-combined -f "$combined_key"
combined_fingerprint=$(ssh-keygen -lf "$combined_key" | awk '{ print $2 }')
cat > "$combined_dir/chezmoi.toml" <<EOF
[data]
tools = ["github-ssh","shell"]
githubSSHKeyPath = "$combined_key"
githubSSHKeyFingerprint = "$combined_fingerprint"
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
apply "$combined_dir"
cmp -s "$combined_key" "$combined_dir/home/.ssh/id_github"
test -f "$combined_dir/home/.ssh/config.d/00-plasticine-github.conf"
test "$(grep -Fc '# BEGIN plasticine-dotfiles github-ssh' "$combined_dir/home/.ssh/config")" -eq 1
cmp -s "$shell_dir/expected-block" "$combined_dir/home/.zshrc"
cmp -s "$repo_dir/dot_zsh_plugins.txt" "$combined_dir/home/.zsh_plugins.txt"
cmp -s "$repo_dir/dot_p10k.zsh" "$combined_dir/home/.p10k.zsh"
cmp -s "$repo_dir/dot_plasticine/zsh/shared.zsh" "$combined_dir/home/.plasticine/zsh/shared.zsh"
apply "$combined_dir"
test "$(grep -Fc '# BEGIN plasticine-dotfiles github-ssh' "$combined_dir/home/.ssh/config")" -eq 1
cmp -s "$combined_key" "$combined_dir/home/.ssh/id_github"
cmp -s "$shell_dir/expected-block" "$combined_dir/home/.zshrc"

# Lazygit composes with each existing feature and all three together. Existing
# blocks stay where the Owner put them, missing blocks use catalog order, and a
# satisfied rerun is byte-identical.
lazygit_block=$test_root/lazygit-block
cat > "$lazygit_block" <<'EOF'
# >>> Plasticine lazygit >>>
alias lg='lazygit'
# <<< Plasticine lazygit <<<
EOF
lazygit_shell_dir=$test_root/lazygit-shell
mkdir -p "$lazygit_shell_dir/home"; write_antidote "$lazygit_shell_dir/home"
cat > "$lazygit_shell_dir/chezmoi.toml" <<'EOF'
[data]
tools = ["lazygit","shell"]
githubSSHKeyPath = ""
githubSSHKeyFingerprint = ""
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
printf 'owner-prefix\n' > "$lazygit_shell_dir/home/.zshrc"
cat "$lazygit_block" >> "$lazygit_shell_dir/home/.zshrc"
printf 'owner-suffix' >> "$lazygit_shell_dir/home/.zshrc"
apply "$lazygit_shell_dir"
grep -n '^# >>> Plasticine shell >>>$' "$lazygit_shell_dir/home/.zshrc" | grep -q '^1:'
grep -n '^owner-prefix$' "$lazygit_shell_dir/home/.zshrc" | grep -q '^10:'
lazygit_shell_before=$(shasum -a 256 "$lazygit_shell_dir/home/.zshrc" | awk '{print $1}')
apply "$lazygit_shell_dir"
test "$lazygit_shell_before" = "$(shasum -a 256 "$lazygit_shell_dir/home/.zshrc" | awk '{print $1}')"

# A Lazygit dry run renders the shared composer but performs no destination
# writes, backups, or tool preparation.
lazygit_dry_dir=$test_root/lazygit-dry
mkdir -p "$lazygit_dry_dir/home"
printf '%s\n' '[data]' 'tools = ["lazygit"]' 'githubSSHKeyPath = ""' \
    'githubSSHKeyFingerprint = ""' 'githubSSHReplaceFingerprint = ""' \
    'githubSSHTest = false' > "$lazygit_dry_dir/chezmoi.toml"
printf '%s\n' owner > "$lazygit_dry_dir/home/.zshrc"
cp "$lazygit_dry_dir/home/.zshrc" "$lazygit_dry_dir/before"
apply "$lazygit_dry_dir" --dry-run
cmp -s "$lazygit_dry_dir/before" "$lazygit_dry_dir/home/.zshrc"
test ! -e "$lazygit_dry_dir/home/.plasticine"

lazygit_ssh_dir=$test_root/lazygit-ssh
mkdir -p "$lazygit_ssh_dir/home/.ssh"; chmod 700 "$lazygit_ssh_dir/home/.ssh"
cat > "$lazygit_ssh_dir/chezmoi.toml" <<EOF
[data]
tools = ["github-ssh","lazygit"]
githubSSHKeyPath = "$combined_key"
githubSSHKeyFingerprint = "$combined_fingerprint"
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
apply "$lazygit_ssh_dir"
cmp -s "$combined_key" "$lazygit_ssh_dir/home/.ssh/id_github"
cmp -s "$lazygit_block" "$lazygit_ssh_dir/home/.zshrc"
test ! -e "$lazygit_ssh_dir/home/.zsh_plugins.txt"
test ! -e "$lazygit_ssh_dir/home/.p10k.zsh"

all_tools_dir=$test_root/all-tools
mkdir -p "$all_tools_dir/home/.ssh"; chmod 700 "$all_tools_dir/home/.ssh"; write_antidote "$all_tools_dir/home"
cat > "$all_tools_dir/chezmoi.toml" <<EOF
[data]
tools = ["github-ssh","lazygit","shell"]
githubSSHKeyPath = "$combined_key"
githubSSHKeyFingerprint = "$combined_fingerprint"
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
apply "$all_tools_dir"
cmp -s "$combined_key" "$all_tools_dir/home/.ssh/id_github"
cat "$shell_dir/expected-block" "$lazygit_block" > "$all_tools_dir/expected-zshrc"
cmp -s "$all_tools_dir/expected-zshrc" "$all_tools_dir/home/.zshrc"
all_tools_before=$(find "$all_tools_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
apply "$all_tools_dir"
all_tools_after=$(find "$all_tools_dir/home" -type f -exec shasum -a 256 {} + | LC_ALL=C sort | shasum -a 256 | awk '{print $1}')
test "$all_tools_before" = "$all_tools_after"

# The non-interactive selection is a set: every CLI-derived option order records
# the same sorted three-tool value before apply.
for requested in 'lazygit shell github-ssh' 'shell github-ssh lazygit' 'github-ssh lazygit shell'; do
    selection_name=$(printf '%s' "$requested" | tr ' ' '-')
    selection_config=$test_root/selection-$selection_name.toml
    PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS="$requested" \
        PLASTICINE_GITHUB_SSH_KEY="$combined_key" PLASTICINE_GITHUB_SSH_TEST=0 PLASTICINE_REPLACE_GITHUB_SSH_KEY=0 \
        "$chezmoi_bin" -S "$repo_dir" -D "$test_root/selection-home" --persistent-state "$test_root/selection-$selection_name.state" \
        init -C "$selection_config" >/dev/null
    grep -Fq 'tools = ["github-ssh","lazygit","shell"]' "$selection_config"
done

malformed_dir=$test_root/malformed
mkdir -p "$malformed_dir/home"
write_antidote "$malformed_dir/home"
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
mkdir -p "$combined_malformed_dir/home/.ssh"
write_antidote "$combined_malformed_dir/home"
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
cat > "$lint_dir/all-chezmoi.toml" <<EOF
[data]
tools = ["github-ssh","lazygit","shell"]
githubSSHKeyPath = "$combined_key"
githubSSHKeyFingerprint = "$combined_fingerprint"
githubSSHReplaceFingerprint = ""
githubSSHTest = false
EOF
for source_script in "$repo_dir"/.chezmoiscripts/*.tmpl; do
    rendered_script=$lint_dir/$(basename "${source_script%.tmpl}")
    for config_file in "$lint_dir/chezmoi.toml" "$lint_dir/shell-chezmoi.toml" "$lint_dir/all-chezmoi.toml"; do
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
for config_file in "$lint_dir/shell-chezmoi.toml" "$lint_dir/all-chezmoi.toml"; do
    rendered_composer=$lint_dir/composer-$(basename "$config_file" .toml)
    "$chezmoi_bin" \
        -S "$repo_dir" \
        -D "$lint_dir/home" \
        -c "$config_file" \
        execute-template < "$repo_dir/.chezmoitemplates/zshrc-integration-blocks" > "$rendered_composer"
    /bin/sh -n "$rendered_composer"
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck "$rendered_composer"
    fi
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
/bin/sh -n "$repo_dir/install.sh"
/bin/sh -n "$repo_dir/lib/shell-bootstrap.sh"
/bin/sh -n "$repo_dir/lib/lazygit-bootstrap.sh"
# The shared composer has selection-dependent template branches; rendered
# consumers above are syntax-checked instead of the unrendered template.
for repository_script in "$repo_dir"/scripts/*.sh; do
    /bin/sh -n "$repository_script"
done
for test_script in "$repo_dir"/tests/*.sh; do
    /bin/sh -n "$test_script"
done
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$repo_dir/private_dot_ssh/modify_private_config"
    shellcheck "$repo_dir/install.sh"
    shellcheck "$repo_dir/lib/shell-bootstrap.sh"
    shellcheck "$repo_dir/lib/lazygit-bootstrap.sh"
    shellcheck "$repo_dir"/scripts/*.sh
    shellcheck "$repo_dir"/tests/*.sh
fi
if command -v zsh >/dev/null 2>&1; then
    zsh -n "$repo_dir/dot_plasticine/zsh/shared.zsh"
    zsh -n "$repo_dir/dot_p10k.zsh"
fi

printf '%s\n' 'integration tests passed'
