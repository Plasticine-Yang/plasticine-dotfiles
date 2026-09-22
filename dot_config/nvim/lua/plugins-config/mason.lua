-- Tool provisioning for the managed LSP and formatter set.
--
-- The installer drives `MasonToolsInstallSync` headlessly during `--neovim`
-- after it has corrected PATH for a fnm-managed Node. At editor start this
-- module only recomputes the same manifest and never installs on its own.
local node_free = { 'marksman' }
local node_required = {}

local ensure_installed = vim.deepcopy(node_free)
if vim.fn.executable('node') == 1 then
  vim.list_extend(ensure_installed, node_required)
end

require('mason').setup({})

-- mason installs executables under stdpath('data')/mason/bin. Put that first so
-- conform and the LSP `cmd` lookups resolve provisioned tools ahead of any host
-- copy, whether or not the directory exists yet.
local mason_bin = vim.fn.stdpath('data') .. '/mason/bin'
vim.env.PATH = mason_bin .. ':' .. (vim.env.PATH or '')

require('mason-tool-installer').setup({
  ensure_installed = ensure_installed,
  -- Never reach the network implicitly on editor start; the installer triggers
  -- provisioning explicitly.
  run_on_start = false,
})

vim.g.plasticine_mason_ensure_installed = ensure_installed
vim.g.plasticine_mason_configured = 1
