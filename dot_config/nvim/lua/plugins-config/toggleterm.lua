local toggleterm = require('toggleterm')
toggleterm.setup({
  size = function(term)
    if term.direction == 'horizontal' then return 20 end
    if term.direction == 'vertical' then return vim.o.columns * 0.4 end
  end,
  open_mapping = [[<c-t>]],
  hide_numbers = true,
  shade_terminals = true,
  shading_factor = 2,
  start_in_insert = true,
  insert_mappings = true,
  persist_size = true,
  direction = 'float',
  close_on_exit = true,
  shell = vim.o.shell,
  float_opts = { border = 'curved', winblend = 0 },
})
vim.api.nvim_create_autocmd('TermOpen', {
  pattern = 'term://*',
  callback = function(args)
    local opts = { noremap = true, buffer = args.buf }
    vim.keymap.set('t', '<C-q>', [[<C-\><C-n>]], opts)
    vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]], opts)
    vim.keymap.set('t', '<C-l>', [[<C-c><C-u>clear<CR>]], opts)
    for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
      vim.keymap.set('t', '<A-' .. key .. '>', [[<C-\><C-n><C-W>]] .. key, opts)
    end
  end,
})
local Terminal = require('toggleterm.terminal').Terminal
local float = Terminal:new({ direction = 'float' })
local horizontal = Terminal:new({ direction = 'horizontal' })
local vertical = Terminal:new({ direction = 'vertical' })
function _G._FLOAT_TERM() float:toggle() end
function _G._HORIZONTAL_TERM() horizontal:toggle() end
function _G._VERTICAL_TERM() vertical:toggle() end
