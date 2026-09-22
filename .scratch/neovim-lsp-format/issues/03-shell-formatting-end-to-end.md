# 03: shell 格式化端到端（不依赖 Node）

**What to build:** 交付第二条纵切：执行 `--neovim` 之后，Owner 可以用 `<leader>f` 对 shell 脚本做格式化，且不依赖 Node。该切片接入格式化调度器并确立"手动格式化、不保存自动格式化"的行为。

**Blocked by:** 02.

**Status:** ready-for-agent

- [ ] 接入 `conform.nvim`，把 `shfmt` 映射到 sh / bash / zsh 等 shell filetype。
- [ ] `ensure_installed` 增加 `shfmt`，使无 Node 环境下也能安装。
- [ ] `<leader>f` 触发对当前缓冲区的格式化；不存在保存时自动格式化的 autocmd。
- [ ] 当外部 formatter 缺失时，格式化按既定回退策略（LSP format fallback）处理，不产生错误弹窗。
- [ ] 测试断言 shell filetype 的 formatter 映射、`<leader>f` 的绑定，以及没有保存自动格式化。
