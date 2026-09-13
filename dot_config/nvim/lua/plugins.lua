local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
local uv = vim.uv or vim.loop
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
  install = { missing = true },
  checker = { enabled = false },
  change_detection = { notify = false },
})
