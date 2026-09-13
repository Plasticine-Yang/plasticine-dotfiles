local ok = pcall(vim.cmd.colorscheme, 'tokyonight')
if not ok then error('neovim: tokyonight colorscheme is unavailable after plugin synchronization') end
