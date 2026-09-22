-- Formatter dispatch. Formatting is always explicit: <leader>f formats the
-- current buffer, and no autocmd rewrites a file on save.
local prettier = { 'prettier' }
local shfmt = { 'shfmt' }

local formatters_by_ft = {
  javascript = prettier,
  javascriptreact = prettier,
  typescript = prettier,
  typescriptreact = prettier,
  json = prettier,
  jsonc = prettier,
  markdown = prettier,
  sh = shfmt,
  bash = shfmt,
  zsh = shfmt,
  dash = shfmt,
  ksh = shfmt,
}

require('conform').setup({
  formatters_by_ft = formatters_by_ft,
  default_format_opts = {
    -- Fall back to the language server when no external formatter is
    -- configured or available, instead of erroring.
    lsp_format = 'fallback',
  },
  format_on_save = false,
})

vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
  require('conform').format({ async = false, lsp_format = 'fallback' })
end, { desc = 'Format buffer' })

vim.g.plasticine_conform_formatters_by_ft = formatters_by_ft
vim.g.plasticine_conform_configured = 1
