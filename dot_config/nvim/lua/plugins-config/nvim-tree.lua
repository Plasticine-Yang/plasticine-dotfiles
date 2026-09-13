local api = require('nvim-tree.api')
local function on_attach(bufnr)
  api.config.mappings.default_on_attach(bufnr)
  local function opts(desc) return { desc = 'nvim-tree: ' .. desc, buffer = bufnr, silent = true, nowait = true } end
  vim.keymap.set('n', 'l', api.node.open.edit, opts('Open'))
  vim.keymap.set('n', 'h', api.node.navigate.parent_close, opts('Close Directory'))
  vim.keymap.set('n', 'o', api.node.open.edit, opts('Open'))
  vim.keymap.set('n', '<CR>', api.node.open.edit, opts('Open'))
  vim.keymap.set('n', 'v', api.node.open.vertical, opts('Open: Vertical Split'))
  vim.keymap.set('n', 's', api.node.open.horizontal, opts('Open: Horizontal Split'))
  vim.keymap.set('n', 'r', api.fs.rename, opts('Rename'))
  vim.keymap.set('n', 'a', api.fs.create, opts('Create'))
  vim.keymap.set('n', 'd', api.fs.remove, opts('Delete'))
  vim.keymap.set('n', 'c', api.fs.copy.node, opts('Copy'))
  vim.keymap.set('n', 'x', api.fs.cut, opts('Cut'))
  vim.keymap.set('n', 'p', api.fs.paste, opts('Paste'))
  vim.keymap.set('n', 'y', api.fs.copy.filename, opts('Copy Name'))
  vim.keymap.set('n', 'Y', api.fs.copy.relative_path, opts('Copy Relative Path'))
  vim.keymap.set('n', 'H', api.tree.toggle_hidden_filter, opts('Toggle Dotfiles'))
  vim.keymap.set('n', 'R', api.tree.reload, opts('Refresh'))
  vim.keymap.set('n', '?', api.tree.toggle_help, opts('Help'))
end
require('nvim-tree').setup({
  on_attach = on_attach, disable_netrw = true, hijack_netrw = true, sort = { sorter = 'case_sensitive' },
  view = { width = 30, side = 'left', signcolumn = 'yes' },
  renderer = { indent_markers = { enable = true } },
  hijack_directories = { enable = true, auto_open = true },
  update_focused_file = { enable = true, update_root = { enable = true } },
  filters = { dotfiles = false }, git = { enable = true, ignore = true, timeout = 500 },
  actions = { open_file = { quit_on_open = false, resize_window = true } },
})
