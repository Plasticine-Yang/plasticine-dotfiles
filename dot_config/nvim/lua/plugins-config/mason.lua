-- Tool provisioning for the managed LSP and formatter set.
--
-- Every entry pins the version recorded in the mason registry when this Release
-- was cut. The pin only approximates reproducibility: mason downloads these
-- artifacts outside the Release snapshot, so they are never covered by the
-- snapshot's digest verification and an upstream version can disappear.
--
-- The installer drives `MasonToolsInstallSync` headlessly during `--neovim`
-- after it has corrected PATH for a fnm-managed Node. At editor start this
-- module only recomputes the same manifest and never installs on its own.
local node_free = {
  { 'marksman', version = '2026-02-08' },
  { 'shfmt', version = 'v3.14.1' },
}

-- typescript-language-server pulls the matching `typescript`/tsserver through
-- its registry `extra_packages`, so it is not requested under its own name.
local node_required = {
  { 'typescript-language-server', version = '6.0.0' },
  { 'bash-language-server', version = '5.8.0' },
  { 'json-lsp', version = '4.10.0' },
  { 'prettier', version = '3.9.8' },
}

local ensure_installed = vim.deepcopy(node_free)
if vim.fn.executable('node') == 1 and vim.fn.executable('npm') == 1 then
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

vim.g.plasticine_mason_ensure_installed = vim.tbl_map(function(entry)
  if type(entry) == 'table' then return entry[1] .. '@' .. entry.version end
  return entry
end, ensure_installed)
vim.g.plasticine_mason_configured = 1
