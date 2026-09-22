#!/bin/sh
set -eu

# Exercise the shipped configuration in a real Neovim process. Plugin modules
# are deterministic local fixtures: this suite must not depend on the network.
repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
nvim_bin=${NVIM_BIN:-$(command -v nvim 2>/dev/null || true)}
[ -n "$nvim_bin" ] || { printf '%s\n' 'Neovim runtime tests require nvim.' >&2; exit 1; }
runtime_root=$(mktemp -d "${TMPDIR:-/tmp}/plasticine-neovim-runtime.XXXXXX")
trap 'rm -rf "$runtime_root"' EXIT HUP INT TERM
home=$runtime_root/home
config=$home/.config/nvim
lazy=$home/.local/share/nvim/lazy/lazy.nvim
mkdir -p "$home/.config" "$lazy/lua/lazy" "$lazy/colors" \
    "$lazy/lua/neoscroll" "$lazy/lua/nvim-surround" \
    "$lazy/lua/nvim-autopairs" "$lazy/lua/nvim-tree" \
    "$lazy/lua/toggleterm" "$lazy/lua/mason" \
    "$lazy/lua/mason-tool-installer" "$lazy/lua/conform"
cp -R "$repo_dir/dot_config/nvim" "$config"
# A previous packer installation must not be sourced alongside lazy plugins.
legacy=$home/.local/share/nvim/site/pack/packer/start/legacy-tree/plugin
mkdir -p "$legacy"
cat > "$legacy/tree.lua" <<'EOF'
vim.g.fixture_legacy_tree_loaded = 1
vim.api.nvim_create_user_command('NvimTreeToggle', function()
  error('legacy packer tree command was loaded')
end, {})
EOF
# The installed Plasticine launcher deliberately supplies its own XDG roots.
# Mirror the fixtures there so the runtime suite also works through that public
# launcher, while distribution-provided `nvim` uses the standard paths above.
mkdir -p "$home/.plasticine/config" "$home/.plasticine/runtime/nvim/data/nvim/lazy"
cp -R "$config" "$home/.plasticine/config/nvim"
ln -s "$lazy" "$home/.plasticine/runtime/nvim/data/nvim/lazy/lazy.nvim"

cat > "$lazy/lua/lazy/init.lua" <<'EOF'
local M = {}
function M.setup(specs, opts)
  assert(opts.local_spec == false)
  vim.g.fixture_lazy_setup = 1
  if vim.lsp then
    local original_enable = vim.lsp.enable
    vim.lsp.enable = function(enabled)
      vim.g.fixture_lsp_enabled = enabled
      if original_enable then return original_enable(enabled) end
    end
  end
  local plugin_specs = {}
  for _, spec in ipairs(specs) do
    plugin_specs[#plugin_specs + 1] = spec[1]
    for _, dependency in ipairs(spec.dependencies or {}) do
      if type(dependency) == 'string' then
        plugin_specs[#plugin_specs + 1] = dependency
      elseif type(dependency) == 'table' and type(dependency[1]) == 'string' then
        plugin_specs[#plugin_specs + 1] = dependency[1]
      end
    end
    if spec[1] == 'smoka7/hop.nvim' then
      assert(spec.opts.keys == 'etovxqpdygfblzhckisuran')
      vim.g.fixture_hop_spec = 1
    elseif spec[1] == 'windwp/nvim-autopairs' and spec.config == true then
      require('nvim-autopairs').setup({})
    end
    if type(spec.config) == 'function' then spec.config() end
  end
  vim.g.fixture_plugin_specs = plugin_specs
end
return M
EOF
cat > "$lazy/lua/neoscroll/init.lua" <<'EOF'
return { setup = function(opts) assert(opts.hide_cursor); vim.g.fixture_neoscroll = 1 end }
EOF
cat > "$lazy/lua/nvim-surround/init.lua" <<'EOF'
return { setup = function() vim.g.fixture_surround = 1 end }
EOF
cat > "$lazy/lua/nvim-autopairs/init.lua" <<'EOF'
return { setup = function() vim.g.fixture_autopairs = 1 end }
EOF
cat > "$lazy/lua/nvim-tree/init.lua" <<'EOF'
return { setup = function(opts)
  assert(type(opts.on_attach) == 'function')
  vim.api.nvim_create_user_command('NvimTreeToggle', function() end, {})
  vim.g.fixture_nvim_tree = 1
end }
EOF
cat > "$lazy/lua/nvim-tree/api.lua" <<'EOF'
local noop = function() end
return {
  config = { mappings = { default_on_attach = noop } },
  node = { open = { edit = noop, vertical = noop, horizontal = noop }, navigate = { parent_close = noop } },
  fs = { rename = noop, create = noop, remove = noop, copy = { node = noop, filename = noop, relative_path = noop }, cut = noop, paste = noop },
  tree = { toggle_hidden_filter = noop, reload = noop, toggle_help = noop, open = noop, close = noop },
}
EOF
cat > "$lazy/lua/toggleterm/init.lua" <<'EOF'
return { setup = function(opts) assert(opts.direction == 'float'); vim.g.fixture_toggleterm = 1 end }
EOF
cat > "$lazy/lua/toggleterm/terminal.lua" <<'EOF'
local Terminal = {}
function Terminal:new(opts)
  assert(opts.direction == 'float' or opts.direction == 'horizontal' or opts.direction == 'vertical')
  return { toggle = function() vim.g.fixture_terminal_toggles = (vim.g.fixture_terminal_toggles or 0) + 1 end }
end
return { Terminal = Terminal }
EOF
cat > "$lazy/lua/mason/init.lua" <<'EOF'
return { setup = function(opts) assert(type(opts) == 'table'); vim.g.fixture_mason = 1 end }
EOF
cat > "$lazy/lua/mason-tool-installer/init.lua" <<'EOF'
return { setup = function(opts)
  assert(type(opts.ensure_installed) == 'table')
  vim.g.fixture_mason_tools = 1
  vim.g.fixture_mason_ensure_installed = opts.ensure_installed
  vim.g.fixture_mason_run_on_start = opts.run_on_start
end }
EOF
cat > "$lazy/lua/conform/init.lua" <<'EOF'
return {
  setup = function(opts)
    vim.g.fixture_conform = 1
    vim.g.fixture_conform_by_ft = opts.formatters_by_ft
    vim.g.fixture_conform_format_on_save = opts.format_on_save
    vim.g.fixture_conform_lsp_format = opts.default_format_opts and opts.default_format_opts.lsp_format
  end,
  format = function(opts)
    vim.g.fixture_conform_format_called = (vim.g.fixture_conform_format_called or 0) + 1
    assert(type(opts.lsp_format) == 'string')
    return {}
  end,
}
EOF
cat > "$lazy/colors/tokyonight.vim" <<'EOF'
let g:colors_name = 'tokyonight-fixture'
EOF

HOME=$home PLASTICINE_HOME=$home/.plasticine XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
    XDG_STATE_HOME=$home/.local/state XDG_CACHE_HOME=$home/.cache \
    "$nvim_bin" --headless \
    '+lua if vim.g.fixture_legacy_tree_loaded then io.stderr:write("legacy packer plugin was loaded alongside lazy plugins\n"); vim.cmd("cquit") end' \
    '+lua local ok, err = pcall(function() local expected = { "fixture_lazy_setup", "fixture_neoscroll", "fixture_surround", "fixture_autopairs", "fixture_hop_spec", "fixture_nvim_tree", "fixture_toggleterm", "plasticine_lsp_configured", "plasticine_conform_configured", "plasticine_mason_configured" }; for _, name in ipairs(expected) do assert(vim.g[name] == 1, name .. " was not configured") end; local managed = { "neovim/nvim-lspconfig", "williamboman/mason.nvim", "WhoIsSethDaniel/mason-tool-installer.nvim", "stevearc/conform.nvim" }; for _, name in ipairs(managed) do assert(vim.tbl_contains(vim.g.fixture_plugin_specs, name), name .. " plugin was not declared") end; assert(vim.tbl_contains(vim.g.plasticine_lsp_servers, "marksman"), "marksman was not registered"); assert(vim.tbl_contains(vim.g.fixture_lsp_enabled, "marksman"), "vim.lsp.enable was not called with marksman"); assert(vim.g.fixture_mason == 1); assert(vim.g.fixture_mason_tools == 1); assert(not vim.g.fixture_mason_run_on_start, "mason-tool-installer installs on start"); local installed = vim.g.fixture_mason_ensure_installed; assert(#installed == 2 and vim.tbl_contains(installed, "marksman") and vim.tbl_contains(installed, "shfmt"), "unexpected ensure_installed: " .. vim.inspect(installed)); local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"; assert(vim.env.PATH:sub(1, #mason_bin) == mason_bin, "mason bin was not prepended to PATH"); assert(vim.g.fixture_conform == 1); assert(vim.g.fixture_conform_lsp_format == "fallback", "lsp_format fallback was not configured"); assert(not vim.g.fixture_conform_format_on_save, "format_on_save was enabled"); local by_ft = vim.g.fixture_conform_by_ft; for _, ft in ipairs({ "sh", "bash", "zsh", "dash", "ksh" }) do assert(vim.tbl_contains(by_ft[ft] or {}, "shfmt"), ft .. " was not mapped to shfmt") end; local format_map = vim.fn.maparg("<leader>f", "n", false, true); assert(format_map and format_map.desc == "Format buffer", "<leader>f was not bound to formatting"); assert(#vim.api.nvim_get_autocmds({ event = "BufWritePre" }) == 0, "a save-time formatting autocmd was registered"); vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<leader>f", true, false, true), "x", false); assert(vim.g.fixture_conform_format_called == 1, "<leader>f did not invoke conform.format"); assert(vim.g.colors_name == "tokyonight-fixture"); assert(vim.fn.maparg("<C-n>", "n") ~= ""); assert(vim.fn.exists(":NvimTreeToggle") == 2); assert(type(_FLOAT_TERM) == "function"); assert(type(_HORIZONTAL_TERM) == "function"); assert(type(_VERTICAL_TERM) == "function"); _FLOAT_TERM(); _HORIZONTAL_TERM(); _VERTICAL_TERM(); assert(vim.g.fixture_terminal_toggles == 3) end); if not ok then io.stderr:write(tostring(err) .. "\n"); vim.cmd("cquit") end' \
    '+qa'
printf '%s\n' 'deterministic real-Neovim runtime tests passed'
