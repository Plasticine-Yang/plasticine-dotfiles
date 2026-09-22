# 02: Markdown LSP 端到端（不依赖 Node）

**What to build:** 交付第一条完整的 LSP 纵切：执行 `--neovim` 之后，Markdown 语言服务器自动就位并可用，即使 Workstation 上没有 Node。该切片同时建立 mason 工具供给机制、安装阶段的供给步骤，以及"缺少 Node 只警告并降级"的行为，供后续切片复用。

**Blocked by:** 01.

**Status:** ready-for-agent

- [ ] 新增 LSP 配置：启用 `marksman`，配置 client capabilities、诊断展示与常用键位（跳转定义、引用、悬停、重命名、代码动作等）。
- [ ] 启用 Neovim 内置 `vim.lsp.completion`，不引入 nvim-cmp 生态。
- [ ] 新增 mason 配置：初始化 mason，把 mason 的 bin 目录前置到 `PATH`，并依据 Node 可用性计算待安装清单。
- [ ] `ensure_installed` 在无 Node 时仍包含 `marksman`。
- [ ] 安装阶段新增工具供给步：在受管配置应用之后，以 headless Neovim 触发 mason 安装当前清单。
- [ ] 缺少 Node 时，供给步退出码为 0，仅在 stderr 打印一次警告，清楚说明被跳过的语言与工具、原因是缺少 Node，以及"安装 fnm 与 Node 后重跑 `--neovim`"的指引。
- [ ] routine 测试中供给步被替换/打桩，断言其被调用且未访问网络。
- [ ] 运行时测试断言无 Node 分支下 Markdown LSP 的启用与 masonry 清单内容。
