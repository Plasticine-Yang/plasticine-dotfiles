-- Language servers wired through the 0.11+ built-in LSP entrypoints. mason
-- decides which binaries are actually provisioned based on the Node toolchain,
-- so the server set is declared here in full and started by `vim.lsp.enable`.
local servers = { 'marksman' }

local capabilities = vim.lsp.protocol.make_client_capabilities()

local function on_attach(_, bufnr)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
  end
  map('n', 'gd', vim.lsp.buf.definition, 'Go to definition')
  map('n', 'gD', vim.lsp.buf.declaration, 'Go to declaration')
  map('n', 'gi', vim.lsp.buf.implementation, 'Go to implementation')
  map('n', 'gr', vim.lsp.buf.references, 'Go to references')
  map('n', 'K', vim.lsp.buf.hover, 'Hover documentation')
  map('n', '<C-k>', vim.lsp.buf.signature_help, 'Signature help')
  map('n', '<leader>rn', vim.lsp.buf.rename, 'Rename symbol')
  map({ 'n', 'v' }, '<leader>ca', vim.lsp.buf.code_action, 'Code action')
  map('n', '[d', vim.diagnostic.goto_prev, 'Previous diagnostic')
  map('n', ']d', vim.diagnostic.goto_next, 'Next diagnostic')
  map('n', '<leader>e', vim.diagnostic.open_float, 'Show diagnostic')
  map('n', '<leader>q', vim.diagnostic.setloclist, 'Diagnostics to location list')
end

-- The managed baseline (Neovim 0.12.5) ships `vim.lsp.config`/`vim.lsp.enable`.
-- Guard them so an older external editor still loads this configuration instead
-- of erroring on an unknown API.
if vim.lsp.config then
  vim.lsp.config('*', { capabilities = capabilities })
  for _, server in ipairs(servers) do
    vim.lsp.config(server, { capabilities = capabilities })
  end
end

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = 'rounded', source = true },
})

vim.api.nvim_create_autocmd('LspAttach', {
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if client and vim.lsp.completion then
      -- Built-in semantic completion; no nvim-cmp ecosystem.
      vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
    end
    on_attach(client, event.buf)
  end,
})

if vim.lsp.enable then
  vim.lsp.enable(servers)
end

vim.g.plasticine_lsp_servers = servers
vim.g.plasticine_lsp_configured = 1
