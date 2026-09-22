# 02: Markdown LSP 端到端（不依赖 Node）

**What to build:** 交付第一条完整的 LSP 纵切：执行 `--neovim` 之后，Markdown 语言服务器自动就位并可用，即使 Workstation 上没有 Node。该切片同时建立 mason 工具供给机制、安装阶段的供给步骤，以及"缺少 Node 只警告并降级"的行为，供后续切片复用。

**Blocked by:** 01.

**Status:** done

- [ ] 新增 LSP 配置：启用 `marksman`，配置 client capabilities、诊断展示与常用键位（跳转定义、引用、悬停、重命名、代码动作等）。
- [ ] 启用 Neovim 内置 `vim.lsp.completion`，不引入 nvim-cmp 生态。
- [ ] 新增 mason 配置：初始化 mason，把 mason 的 bin 目录前置到 `PATH`，并依据 Node 可用性计算待安装清单。
- [ ] `ensure_installed` 在无 Node 时仍包含 `marksman`。
- [ ] 安装阶段新增工具供给步：在受管配置应用之后，以 headless Neovim 触发 mason 安装当前清单。
- [ ] 缺少 Node 时，供给步退出码为 0，仅在 stderr 打印一次警告，清楚说明被跳过的语言与工具、原因是缺少 Node，以及"安装 fnm 与 Node 后重跑 `--neovim`"的指引。
- [ ] routine 测试中供给步被替换/打桩，断言其被调用且未访问网络。
- [ ] 运行时测试断言无 Node 分支下 Markdown LSP 的启用与 masonry 清单内容。

## Comments

2026-09-23: Implemented on `feat/neovim-lsp-format` in commit a264ae7.

- `lua/plugins-config/lsp.lua` 通过 0.11+ 内置入口配置 `marksman`、共享 capabilities、诊断展示与 `gd`/`gr`/`K`/`<leader>rn`/`<leader>ca` 等键位，并在 `LspAttach` 中启用内置 `vim.lsp.completion`（无 nvim-cmp）。
- `lua/plugins-config/mason.lua` 初始化 mason、把 `stdpath('data')/mason/bin` 前置到 `PATH`，并按 `vim.fn.executable('node')` 计算 `ensure_installed`；`run_on_start` 保持关闭。
- `lib/neovim-bootstrap.sh` 新增 `plasticine_neovim_supply_tools`：供给步在插件同步之后、runtime readiness 之前 headless 运行 `MasonToolsInstallSync`；无 Node 时只部署不依赖 Node 的工具并在 stderr 打印一次警告，退出码 0；Preview 文案配额同步为 12。
- `tests/neovim.sh` 从受控 PATH 中排除 node/npm/fnm，断言供给步被调用、无网络、无 Node 分支退出 0 且警告恰好一次、重跑幂等。
- `tests/neovim-runtime.sh` 新增 mason/mason-tool-installer/conform fixture，捕获 `vim.lsp.enable` 调用与 `ensure_installed`，断言无 Node 时清单为 `{marksman}`。
- 验证：`tests/neovim-runtime.sh`、`tests/neovim.sh`、`tests/installer.sh` 全部通过。
