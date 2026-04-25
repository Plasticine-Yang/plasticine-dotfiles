-- Modes
--   normal_mode = "n",
--   insert_mode = "i",
--   visual_mode = "v",
--   visual_block_mode = "x",
--   term_mode = "t",
--   command_mode = "c"
--   operator_pending_mode = "o"

-- 按键映射配置
local opt = {
  -- 不递归映射
  noremap = true,
  -- 不输出多余信息
  silent = true
}

-- vim 全局按键映射 api
local map = vim.api.nvim_set_keymap

-- leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ================ scroll ================

-- J K 小幅垂直移动
map('n', 'J', '5j', opt)
map('n', 'K', '5k', opt)

-- 垂直方向移动时始终保持光标在中央
map('n', 'j', 'jzz', opt)
map('n', 'k', 'kzz', opt)
map('n', '<C-d>', '<C-d>zz', opt)
map('n', '<C-u>', '<C-u>zz', opt)
map('n', '<C-f>', '<C-f>zz', opt)
map('n', '<C-b>', '<C-b>zz', opt)

-- ================ move ================

-- <S-h> 移动到行首
map('n', '<S-h>', '^', opt)
-- <S-l> 移动到行尾
map('n', '<S-l>', '$', opt)

-- ================ file ================

-- <C-s> save file
map('n', '<C-s>', ':w<CR>', opt)

-- qq -- Exit without modifying anything.
map('n', 'qq', ':q!<CR>', opt)

-- ================ nvim-tree ================

-- <C-n> toggle file tree
map('n', '<C-n>', ':NvimTreeToggle<CR>', opt)

-- ================ hop.nvim ================
map('n', '<leader><leader>h', ':HopAnywhereBC<CR>', opt)
map('n', '<leader><leader>l', ':HopAnywhereAC<CR>', opt)

-- ================ INSERT MODE ================

-- jk --> <Esc>
map('i', 'jk', '<Esc>', opt)

-- <C-hjkl> 移动光标
map('i', '<C-h>', '<Esc>i', opt)
map('i', '<C-j>', '<Esc>ja', opt)
map('i', '<C-k>', '<Esc>ka', opt)
map('i', '<C-l>', '<Esc>la', opt)

-- ================ VISUAL MODE ================

-- <S-h> 移动到行首
map('v', '<S-h>', '^', opt)
-- <S-l> 移动到行尾
map('v', '<S-l>', '$', opt)

-- ================ operator_pending_mode ================

-- <S-h> 移动到行首
map('o', '<S-h>', '^', opt)
-- <S-l> 移动到行尾
map('o', '<S-l>', '$', opt)
