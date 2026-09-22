# 01: 接入受管插件与扩展受管文件清单

**What to build:** 把本次 LSP 与格式化所需的 4 个插件纳入 Base Dotfiles 的受管范围，并把受管 Neovim 配置文件清单从 9 个扩为 12 个，使发布版安装能够恢复并加载这些插件与配置。这是一个 prefactor：它本身不改变编辑器行为，但让后续每个纵向切片都能在受管快照与受管文件边界内落地。

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] `neovim/nvim-lspconfig`、`williamboman/mason.nvim`、`WhoIsSethDaniel/mason-tool-installer.nvim`、`stevearc/conform.nvim` 已在插件声明中启用，并登记进 Release 受管插件快照，每行包含固定 40 位 commit 与探针文件。
- [ ] 受管 Neovim 配置文件清单从 9 个扩为 12 个，新增 LSP、格式化、mason 三个配置模块目标。
- [ ] chezmoi 配置模板、安装器 Preview 文案与 README 的受管文件列表三处表述一致，不再出现 "nine" 之类的旧计数。
- [ ] `tests/neovim-runtime.sh` 为 4 个新插件提供本地 fixture 桩，routine 测试不联网、不真实安装任何工具。
- [ ] `tests/neovim.sh`、`tests/installer.sh`、`tests/combined-installation.sh` 中与受管文件数量、安装步骤相关的断言已更新。
- [ ] 快照构建与恢复流程（`scripts/build-managed-plugins.sh`、`lib/managed-plugins.sh`）对新增行无需特殊分支即可通过。
