#!/bin/sh
set -eu

# This suite intentionally reaches current upstream plugin repositories. It is
# opt-in so routine deterministic tests never depend on live releases.
[ "${PLASTICINE_LIVE_NEOVIM_SMOKE:-}" = 1 ] || {
    printf '%s\n' 'Set PLASTICINE_LIVE_NEOVIM_SMOKE=1 to run the live current-plugin smoke.' >&2
    exit 2
}
repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
nvim_bin=${NVIM_BIN:-$(command -v nvim 2>/dev/null || true)}
[ -n "$nvim_bin" ] || { printf '%s\n' 'live Neovim smoke requires nvim.' >&2; exit 1; }
smoke_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-neovim-live.XXXXXX")
trap 'rm -rf "$smoke_root"' EXIT HUP INT TERM
home=$smoke_root/home
mkdir -p "$home/.config"
cp -R "$repo_dir/dot_config/nvim" "$home/.config/nvim"
run_nvim() {
    HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
        XDG_STATE_HOME=$home/.local/state XDG_CACHE_HOME=$home/.cache \
        "$nvim_bin" --headless "$@"
}
run_nvim '+Lazy! sync' '+lua vim.wait(2000)' '+qa'
run_nvim '+lua local ok, err = pcall(function() assert(vim.g.colors_name:match("^tokyonight")); assert(vim.fn.maparg("<C-n>", "n") ~= ""); assert(type(_FLOAT_TERM) == "function"); assert(type(_HORIZONTAL_TERM) == "function"); assert(type(_VERTICAL_TERM) == "function"); assert(vim.fn.exists(":NvimTreeToggle") == 2); require("nvim-tree.api").tree.open(); require("nvim-tree.api").tree.close(); _FLOAT_TERM(); vim.wait(200); _FLOAT_TERM() end); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit") end' '+qa'
printf '%s\n' 'real current-upstream Neovim smoke passed'
