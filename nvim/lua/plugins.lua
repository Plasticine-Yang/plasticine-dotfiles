-- 自动安装 packer.nvim
-- 插件安装目录
-- ~/.local/share/nvim/site/pack/packer/
local ensure_packer = function()
  local fn = vim.fn
  local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
  if fn.empty(fn.glob(install_path)) > 0 then
    vim.notify("installing packer.nvim...")

    fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path })
    vim.cmd [[packadd packer.nvim]]

    vim.notify("packer.nvim was successfully installed.")
    return true
  end
  return false
end

local packer_bootstrap = ensure_packer()

-- Use a protected call so we don't error out on first use
local status_ok, packer = pcall(require, "packer")
if not status_ok then
  vim.notify("packer.nvim is not installed!")
  return
end

packer.startup({
  function(use)
    use 'wbthomason/packer.nvim'

    -- ================ colorschemes ================

    -- tokyonight
    use 'folke/tokyonight.nvim'

    -- ==============================================

    -- 平滑滚动
    use 'karb94/neoscroll.nvim'

    -- surround.nvim
    use 'ur4ltz/surround.nvim'

    -- nvim-autopairs
    use({
      'windwp/nvim-autopairs',
      config = function()
        require('nvim-autopairs').setup({})
      end,
    })

    -- hop.nvim 一个 easymotion + sneak 的聚合插件
    use({
      'phaazon/hop.nvim',
      branch = 'v2', -- optional but strongly recommended
      config = function()
        -- you can configure Hop the way you like here; see :h hop-config
        require('hop').setup({ keys = 'etovxqpdygfblzhckisuran' })
      end,
    })

    -- nvim-tree.lua 文件树
    use({
      'nvim-tree/nvim-tree.lua',
      requires = {
        'nvim-tree/nvim-web-devicons',
      },
      config = function()
        require('plugins-config.nvim-tree')
      end,
    })

    -- Automatically set up your configuration after cloning packer.nvim
    -- Put this at the end after all plugins
    if packer_bootstrap then
      require('packer').sync()
    end
  end,

  config = {
    -- using a floating window for command outputs
    display = {
      open_fn = require('packer.util').float
    }
  }
})

-- 保存 plugins.lua 文件自动安装插件
pcall(vim.cmd, [[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerSync
  augroup end
]])
