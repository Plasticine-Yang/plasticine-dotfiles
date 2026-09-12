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

lint_dir=$test_root/lint
mkdir -p "$lint_dir/home"
cp "$replace_dir/chezmoi.toml" "$lint_dir/chezmoi.toml"
for source_script in "$repo_dir"/.chezmoiscripts/*.tmpl; do
    rendered_script=$lint_dir/$(basename "${source_script%.tmpl}")
    "$chezmoi_bin" \
        -S "$repo_dir" \
        -D "$lint_dir/home" \
        -c "$lint_dir/chezmoi.toml" \
        execute-template < "$source_script" > "$rendered_script"
    if grep -q '[^[:space:]]' "$rendered_script"; then
        /bin/sh -n "$rendered_script"
        if command -v shellcheck >/dev/null 2>&1; then
            shellcheck "$rendered_script"
        fi
    fi
done
/bin/sh -n "$repo_dir/private_dot_ssh/modify_private_config"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$repo_dir/private_dot_ssh/modify_private_config"
fi

printf '%s\n' 'integration tests passed'
