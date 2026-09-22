# 03: shell 格式化端到端（不依赖 Node）

**What to build:** 交付第二条纵切：执行 `--neovim` 之后，Owner 可以用 `<leader>f` 对 shell 脚本做格式化，且不依赖 Node。该切片接入格式化调度器并确立"手动格式化、不保存自动格式化"的行为。

**Blocked by:** 02.

**Status:** done

- [ ] 接入 `conform.nvim`，把 `shfmt` 映射到 sh / bash / zsh 等 shell filetype。
- [ ] `ensure_installed` 增加 `shfmt`，使无 Node 环境下也能安装。
- [ ] `<leader>f` 触发对当前缓冲区的格式化；不存在保存时自动格式化的 autocmd。
- [ ] 当外部 formatter 缺失时，格式化按既定回退策略（LSP format fallback）处理，不产生错误弹窗。
- [ ] 测试断言 shell filetype 的 formatter 映射、`<leader>f` 的绑定，以及没有保存自动格式化。

## Comments

2026-09-23: Implemented on `feat/neovim-lsp-format` in commit a7af3be.

- `lua/plugins-config/conform.lua` 把 `shfmt` 映射到 sh/bash/zsh/dash/ksh，`default_format_opts = { lsp_format = 'fallback' }`，`format_on_save = false`，并绑定 `<leader>f`。
- `lua/plugins-config/mason.lua` 的 Node-free 清单加入 `shfmt`；降级警告同步说明 shell 格式化仍可用。
- `tests/neovim-runtime.sh` 断言 shell filetype 映射、`<leader>f` 的绑定与实际触发、`lsp_format` 回退，以及不存在 `BufWritePre` 自动格式化 autocmd。
- 验证：`tests/neovim-runtime.sh` 通过。
