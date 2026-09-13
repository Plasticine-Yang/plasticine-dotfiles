#!/bin/sh
set -eu

repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
chezmoi_bin=${CHEZMOI_BIN:-$(command -v chezmoi 2>/dev/null || true)}
[ -n "$chezmoi_bin" ] || { printf '%s\n' 'neovim tests require chezmoi.' >&2; exit 1; }

test_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-neovim-test.XXXXXX")
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
config=$test_root/chezmoi.toml
PLASTICINE_NONINTERACTIVE=1 PLASTICINE_TOOLS=neovim \
    "$chezmoi_bin" -S "$repo_dir" -D "$test_root/home" \
    --persistent-state "$test_root/state" init -C "$config" >/dev/null
grep -Fq 'tools = ["neovim"]' "$config"

fixture_bin=$test_root/bin
home=$test_root/home
mkdir -p "$fixture_bin" "$home"
cat > "$fixture_bin/curl" <<'EOF'
#!/bin/sh
printf '%s\n' curl >> "$PLASTICINE_NEOVIM_TEST_CALLS"
printf '%s\n' '{"tag_name":"v0.12.4"}'
EOF
cat > "$fixture_bin/nvim" <<'EOF'
#!/bin/sh
case $1 in
  --version) printf '%s\n' 'NVIM v0.12.4' ;;
  --headless) printf 'nvim %s\n' "$*" >> "$PLASTICINE_NEOVIM_TEST_CALLS" ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$fixture_bin"/*
calls=$test_root/calls
: > "$calls"
PATH=$fixture_bin:$PATH PLASTICINE_NEOVIM_TEST_CALLS=$calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$config" \
    --persistent-state "$test_root/state" diff --no-pager >/dev/null
[ ! -s "$calls" ] || { printf '%s\n' 'Neovim Preview accessed the network/editor.' >&2; exit 1; }
PATH=$fixture_bin:$PATH PLASTICINE_NEOVIM_TEST_CALLS=$calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$config" \
    --persistent-state "$test_root/state" apply --no-tty >/dev/null
[ "$(find "$home/.config/nvim" -type f | wc -l | tr -d ' ')" -eq 9 ]
grep -Fq 'Lazy! sync' "$calls"
grep -Fq 'NvimTreeToggle' "$calls"
printf 'owner\n' > "$home/.config/nvim/lua/local.lua"
printf 'changed\n' > "$home/.config/nvim/init.lua"
chmod 600 "$home/.config/nvim/init.lua"
PATH=$fixture_bin:$PATH PLASTICINE_NEOVIM_TEST_CALLS=$calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$config" \
    --persistent-state "$test_root/state" apply --no-tty >/dev/null
[ -f "$home/.config/nvim/lua/local.lua" ]
[ "$(stat -f '%Lp' "$home/.config/nvim/init.lua" 2>/dev/null || stat -c '%a' "$home/.config/nvim/init.lua")" = 600 ]
backup=$(find "$home/.plasticine/backups/neovim" -name 'init.lua.plasticine-backup-*')
grep -Fxq changed "$backup"

# Preview/cancellation never performs the release query or plugin operation.
: > "$calls"
PATH=$fixture_bin:$PATH PLASTICINE_NEOVIM_TEST_CALLS=$calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$home" -c "$config" \
    --persistent-state "$test_root/state" diff --no-pager >/dev/null
[ ! -s "$calls" ]

# Missing/outdated/unhealthy editors and metadata failures stop before config.
for scenario in missing outdated unhealthy lookup; do
    case_home=$test_root/$scenario-home
    case_bin=$test_root/$scenario-bin
    mkdir -p "$case_home" "$case_bin"
    cp "$fixture_bin/curl" "$case_bin/curl"
    cp "$fixture_bin/nvim" "$case_bin/nvim"
    case $scenario in
        missing) rm "$case_bin/nvim" ;;
        outdated) sed 's/NVIM v0.12.4/NVIM v0.11.0/' "$fixture_bin/nvim" > "$case_bin/nvim.tmp"; mv "$case_bin/nvim.tmp" "$case_bin/nvim"; chmod +x "$case_bin/nvim" ;;
        unhealthy) sed 's/printf '\''%s\\n'\'' '\''NVIM v0.12.4'\''/exit 1/' "$fixture_bin/nvim" > "$case_bin/nvim.tmp"; mv "$case_bin/nvim.tmp" "$case_bin/nvim"; chmod +x "$case_bin/nvim" ;;
        lookup) printf '#!/bin/sh\nexit 1\n' > "$case_bin/curl"; chmod +x "$case_bin/curl" ;;
    esac
    if PATH=$case_bin:/usr/bin:/bin PLASTICINE_NEOVIM_TEST_CALLS=$calls \
        "$chezmoi_bin" -S "$repo_dir" -D "$case_home" -c "$config" \
        --persistent-state "$test_root/$scenario-state" apply --no-tty >/dev/null 2>&1; then
        printf 'scenario unexpectedly succeeded: %s\n' "$scenario" >&2; exit 1
    fi
    [ ! -e "$case_home/.config/nvim/init.lua" ]
done

# Competing/default-root and selected-target conflicts are rejected locally.
for scenario in init-vim symlink; do
    case_home=$test_root/conflict-$scenario
    mkdir -p "$case_home/.config/nvim"
    case $scenario in
        init-vim) printf 'set number\n' > "$case_home/.config/nvim/init.vim" ;;
        symlink) ln -s owner "$case_home/.config/nvim/init.lua" ;;
    esac
    if "$chezmoi_bin" -S "$repo_dir" -D "$case_home" -c "$config" \
        --persistent-state "$test_root/conflict-$scenario-state" apply --no-tty >/dev/null 2>&1; then
        printf 'configuration conflict unexpectedly accepted: %s\n' "$scenario" >&2; exit 1
    fi
done
if NVIM_APPNAME=alternate "$chezmoi_bin" -S "$repo_dir" -D "$test_root/appname-home" \
    -c "$config" --persistent-state "$test_root/appname-state" apply --no-tty >/dev/null 2>&1; then
    printf '%s\n' 'NVIM_APPNAME unexpectedly accepted.' >&2; exit 1
fi

# A post-configuration native failure is nonzero and a clean retry succeeds.
failure_home=$test_root/plugin-failure-home
mkdir -p "$failure_home"
cat > "$fixture_bin/nvim-failure" <<'EOF'
#!/bin/sh
case $1 in --version) printf '%s\n' 'NVIM v0.12.4' ;; --headless) exit 1 ;; esac
EOF
chmod +x "$fixture_bin/nvim-failure"
mv "$fixture_bin/nvim" "$fixture_bin/nvim-good"
cp "$fixture_bin/nvim-failure" "$fixture_bin/nvim"
if PATH=$fixture_bin:$PATH PLASTICINE_NEOVIM_TEST_CALLS=$calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$failure_home" -c "$config" \
    --persistent-state "$test_root/failure-state" apply --no-tty >/dev/null 2>&1; then
    printf '%s\n' 'plugin failure unexpectedly succeeded.' >&2; exit 1
fi
[ -f "$failure_home/.config/nvim/init.lua" ]
mv "$fixture_bin/nvim-good" "$fixture_bin/nvim"
PATH=$fixture_bin:$PATH PLASTICINE_NEOVIM_TEST_CALLS=$calls \
    "$chezmoi_bin" -S "$repo_dir" -D "$failure_home" -c "$config" \
    --persistent-state "$test_root/failure-state" apply --no-tty >/dev/null

"$repo_dir/install.sh" --help > "$test_root/help"
grep -Fq -- '--neovim' "$test_root/help"
printf '%s\n' 'neovim entrypoint tests passed'
