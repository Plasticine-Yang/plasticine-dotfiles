-- Isolate legacy pack/*/start plugins before any require can discover them.
-- lazy.nvim owns plugin loading and applies the same packpath reset at setup.
vim.opt.packpath = { vim.env.VIMRUNTIME }

require('basic')
require('keybindings')
require('plugins')
require('colorschema')
