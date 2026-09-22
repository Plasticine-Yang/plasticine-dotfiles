local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
local uv = vim.uv or vim.loop
local release_snapshot = vim.env.PLASTICINE_MANAGED_PLUGINS_ARCHIVE ~= nil
  and vim.env.PLASTICINE_MANAGED_PLUGINS_ARCHIVE ~= ''
  or uv.fs_stat(lazypath .. '/.git/plasticine-release-snapshot') ~= nil
if not uv.fs_stat(lazypath) then
  local output = vim.fn.system({
    'git', 'clone', '--filter=blob:none', '--branch=stable',
    'https://github.com/folke/lazy.nvim.git', lazypath,
  })
  if vim.v.shell_error ~= 0 then error('Failed to clone lazy.nvim:\n' .. output) end
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  { 'folke/tokyonight.nvim', lazy = false, priority = 1000 },
  -- Language tooling is part of the editor baseline: mason provides the
  -- binaries, nvim-lspconfig describes the servers, and conform dispatches
  -- external formatters. All three load eagerly so PATH and diagnostics are
  -- ready before the first buffer.
  {
    'williamboman/mason.nvim',
    lazy = false,
    dependencies = { 'WhoIsSethDaniel/mason-tool-installer.nvim' },
    config = function() require('plugins-config.mason') end,
  },
  { 'neovim/nvim-lspconfig', lazy = false, config = function() require('plugins-config.lsp') end },
  { 'stevearc/conform.nvim', lazy = false, config = function() require('plugins-config.conform') end },
  { 'karb94/neoscroll.nvim', config = function() require('plugins-config.neoscroll') end },
  { 'kylechui/nvim-surround', config = function() require('plugins-config.surround') end },
  { 'windwp/nvim-autopairs', config = true },
  {
    'smoka7/hop.nvim',
    keys = {
      { '<leader><leader>h', '<cmd>HopAnywhereBC<CR>', mode = 'n', desc = 'Hop backward' },
      { '<leader><leader>l', '<cmd>HopAnywhereAC<CR>', mode = 'n', desc = 'Hop forward' },
    },
    opts = { keys = 'etovxqpdygfblzhckisuran' },
  },
  {
    'nvim-tree/nvim-tree.lua',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    config = function() require('plugins-config.nvim-tree') end,
  },
  { 'akinsho/toggleterm.nvim', config = function() require('plugins-config.toggleterm') end },
}, {
  local_spec = false,
  -- A released install restores every managed checkout before Neovim starts.
  -- Suppress implicit Git clones while its snapshot marker remains; explicit
  -- lazy.nvim commands stay available when the Owner wants upstream changes.
  install = { missing = not release_snapshot },
  checker = { enabled = false },
  change_detection = { notify = false },
})
