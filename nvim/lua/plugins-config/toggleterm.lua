local status_ok, toggleterm = pcall(require, "toggleterm")
if not status_ok then
  return
end

toggleterm.setup({
  size = function(term)
    if term.direction == "horizontal" then
      return 20
    elseif term.direction == "vertical" then
      return vim.o.columns * 0.4
    end
  end,
  open_mapping = [[<c-t>]],
  hide_numbers = true,
  shade_filetypes = {},
  shade_terminals = true,
  shading_factor = 2,
  start_in_insert = true,
  insert_mappings = true,
  persist_size = true,
  direction = "float",
  close_on_exit = true,
  shell = vim.o.shell,
  float_opts = {
    border = "curved",
    winblend = 0,
    highlights = {
      border = "Normal",
      background = "Normal",
    },
  },
})

function _G.set_terminal_keymaps()
  local opts = { noremap = true }
  -- 改为 Ctrl + q 退出终端模式，避免与 zsh 的 jk 冲突
  vim.api.nvim_buf_set_keymap(0, 't', '<C-q>', [[<C-\><C-n>]], opts)
  -- 保留 Esc 作为备用
  vim.api.nvim_buf_set_keymap(0, 't', '<esc>', [[<C-\><C-n>]], opts)
  -- 修复 Ctrl + l 清屏（使用终端控制序列）
  vim.api.nvim_buf_set_keymap(0, 't', '<C-l>', [[<C-c><C-u>clear<CR>]], opts)
  -- 分屏切换（使用 Alt 键）
  vim.api.nvim_buf_set_keymap(0, 't', '<A-h>', [[<C-\><C-n><C-W>h]], opts)
  vim.api.nvim_buf_set_keymap(0, 't', '<A-j>', [[<C-\><C-n><C-W>j]], opts)
  vim.api.nvim_buf_set_keymap(0, 't', '<A-k>', [[<C-\><C-n><C-W>k]], opts)
  vim.api.nvim_buf_set_keymap(0, 't', '<A-l>', [[<C-\><C-n><C-W>l]], opts)
end

vim.cmd('autocmd! TermOpen term://* lua set_terminal_keymaps()')

-- 定义不同类型的终端
local Terminal = require('toggleterm.terminal').Terminal

-- 浮窗终端
local float_terminal = Terminal:new({
  direction = "float",
  on_open = function(term)
    vim.cmd("startinsert!")
  end,
  on_close = function(term)
    vim.cmd("startinsert!")
  end,
})

-- 水平终端
local horizontal_terminal = Terminal:new({
  direction = "horizontal",
  on_open = function(term)
    vim.cmd("startinsert!")
  end,
  on_close = function(term)
    vim.cmd("startinsert!")
  end,
})

-- 垂直终端
local vertical_terminal = Terminal:new({
  direction = "vertical",
  on_open = function(term)
    vim.cmd("startinsert!")
  end,
  on_close = function(term)
    vim.cmd("startinsert!")
  end,
})

-- 快捷函数
function _FLOAT_TERM()
  float_terminal:toggle()
end

function _HORIZONTAL_TERM()
  horizontal_terminal:toggle()
end

function _VERTICAL_TERM()
  vertical_terminal:toggle()
end
