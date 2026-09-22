# Neovim LSP 与格式化支持（javascript / typescript / shell / json / markdown）

Status: ready-for-agent

## Problem Statement

Owner 希望在 Neovim 中获得常见语言的 LSP 与格式化能力，覆盖 javascript、typescript、shell、json、markdown 五类。当前受管配置只保留编辑偏好、Tokyo Night、平滑滚动、surround、自动配对、Hop、nvim-tree 和终端快捷键；`plugins.lua` 中没有任何 LSP 客户端或 formatter，安装 `--neovim` 只恢复编辑器与插件快照，不会准备任何语言服务器或格式化工具。

Owner 的期望是"选完就装完"：执行 `plasticine -y --neovim`（必要时搭配 `--fnm`）之后，LSP 与格式化自动就位，不需要手动运行 `npm i -g`。此前评估过的"只写配置、缺工具让用户自装"方案被明确否决，因为它违背这一初衷。

同时 Owner 给出了两条边界：

- `--fnm` 保持现状：只维护 manager，不自动安装 Node 版本，也不安装 pnpm。
- 当 `--neovim` 找不到可用的 Node 工具链时，跳过依赖 Node 的部分，只打印警告，不失败。

## Solution

在 `--neovim` Feature 中新增一步"LSP/format 工具供给"，用 mason.nvim 作为供给机制，在**安装阶段**以 headless Neovim 一次性装齐语言服务器与格式化工具；受管配置新增 LSP 客户端、格式化调度与 mason 接线。工具供给在恢复插件快照、应用受管配置之后执行。

Neovim 侧使用其 0.11+ 内置的 LSP 能力（基线 0.12.5），因此只引入最小插件集：

- `neovim/nvim-lspconfig`：各语言服务器的启动定义（`cmd` / `root_markers` / `filetypes`）。
- `williamboman/mason.nvim`：工具供给引擎。
- `WhoIsSethDaniel/mason-tool-installer.nvim`：按运行时计算出的清单安装 server 与 formatter。
- `stevearc/conform.nvim`：按 filetype 调度外部 formatter。

补全使用内置 `vim.lsp.completion`，不引入 nvim-cmp 生态。格式化只提供手动 `<leader>f`，不做保存时自动格式化。

工具供给按 Node 可用性降级：

- **Node + npm 可用** → 安装全部 6 个工具。
- **不可用** → 只安装不依赖 Node 的 `marksman`（Markdown LSP）与 `shfmt`（shell formatter），跳过依赖 Node 的 4 项，打印一次性明确警告，安装整体成功。

`--fnm` 模块本身不做任何修改。安装器在 `--neovim` 的供给步内自行检测 Node；若 fnm 已安装但 Node 尚未进入 `PATH`，通过 `fnm env` 解析出 Node bin 目录后注入，避免误判为"没有 Node"。

## User Stories

1. 作为 Owner，我希望执行 `plasticine -y --neovim` 后五门语言的 LSP 与格式化自动可用，这样我无需手动安装任何工具。
2. 作为 Owner，我希望 javascript / typescript 使用 `typescript-language-server`，并按 `package.json` / `tsconfig.json` / `jsconfig.json` / `.git` 定位项目根目录。
3. 作为 Owner，我希望 shell 使用 `bash-language-server`，json 使用 `vscode-json-language-server`，markdown 使用 `marksman`。
4. 作为 Owner，我希望 javascript / typescript / json / markdown 的格式化由 `prettier` 提供，shell 的格式化由 `shfmt` 提供。
5. 作为 Owner，我希望格式化只在我显式按下 `<leader>f` 时发生，不希望在保存时自动改写文件。
6. 作为 Owner，我希望 LSP 提供跳转定义、引用、悬停、重命名、代码动作与诊断导航等常用操作，并使用内置 `vim.lsp.completion` 提供语义补全。
7. 作为 Owner，我希望缺少 Node 工具链时 `--neovim` 只警告并跳过依赖 Node 的部分，而不是失败、也不是要求我手动安装。
8. 作为 Owner，我希望缺少 Node 时 Markdown 的 LSP 与 shell 的格式化仍然可用，并在警告中清楚说明哪些能力被跳过以及如何补齐。
9. 作为 Owner，我希望在补齐 Node 后重跑 `--neovim` 能把剩余工具补齐，且重复执行是幂等的。
10. 作为 Owner，我希望 `--fnm` 的行为与现在完全一致，不因本次改动而自动安装 Node 版本或 pnpm。
11. 作为 Owner，我希望新插件与配置文件全部由受管清单与 Release 快照覆盖，使发布版安装可复现。
12. 作为 Owner，我希望 routine 测试不因工具供给而联网，也不在我真实的机器上安装任何工具。
13. 作为 Owner，我希望文档明确说明 mason 下载的工具不在 Release 的独立签名/digest 校验范围内，只能靠固定版本号近似可复现。

## Implementation Decisions

### 依赖检测与降级

- 供给步以 `node` 与 `npm` 是否可执行为准。若 `fnm` 存在且 `node` 不在 `PATH`，先通过 `fnm env`（或等价的原生解析）把 fnm 管理的 Node bin 目录前置到 `PATH` 再判定。
- Node 可用时，`ensure_installed` 包含全部 6 个 mason 包；不可用时只包含 `marksman` 与 `shfmt`。
- 降级路径必须**退出码为 0**，仅在 stderr 打印一次警告，内容需包含：被跳过的语言与工具、原因是缺少 Node、以及"安装 fnm 与 Node 后重跑 `--neovim`"的指引。
- `ensure_installed` 在 Neovim 启动时依据 `vim.fn.executable('node')` 与 `vim.fn.executable('npm')` 计算（两者齐备才算可用，避免安装了 Node 却缺少 npm 时清单与警告互相矛盾），因此安装器只需保证 `PATH` 正确，无需额外传递参数。

### 工具矩阵

| 语言 | LSP server（mason 包） | formatter（mason 包） | 依赖 Node |
| --- | --- | --- | --- |
| javascript / typescript | `typescript-language-server`（及 `typescript`） | `prettier` | 是 |
| shell | `bash-language-server` | `shfmt` | 否（仅 formatter） |
| json | `vscode-langservers-extracted` | `prettier` | 是 |
| markdown | `marksman` | `prettier` | 否（LSP）/ 是（formatter） |

- server 在 `nvim-lspconfig` 中的名称分别为 `ts_ls`、`bashls`、`jsonls`、`marksman`，统一用 `vim.lsp.enable` 启用。
- `mason.nvim` 的 bin 目录（`stdpath('data')/mason/bin`）在配置加载时前置到 `PATH`，使 `conform` 与 LSP `cmd` 能发现工具。
- `mason-tool-installer` 不设置 `run_on_start`，避免编辑器每次启动都尝试联网安装；仅在安装阶段显式触发。

### 安装阶段流程

1. `--fnm`（若被选择）按现有逻辑准备 manager，不做额外动作。
2. `--neovim` 恢复编辑器发行版、从 Release 快照恢复插件、应用受管配置（现有流程不变）。
3. 新增供给步：检测 Node（必要时经 fnm 解析并注入 `PATH`），随后 headless 运行 `MasonToolsInstallSync`，安装当前 `ensure_installed` 清单。
4. 继续执行现有的 runtime readiness 检查；供给步失败时应报告并返回非零，但 Node 缺失导致的降级不算失败。

### 受管文件与插件

- `plugins.lua` 新增 4 个插件：`neovim/nvim-lspconfig`、`williamboman/mason.nvim`、`WhoIsSethDaniel/mason-tool-installer.nvim`、`stevearc/conform.nvim`。
- 新增 `lua/plugins-config/lsp.lua`：`vim.lsp.enable`、capabilities、诊断配置、键位（`gd` / `gr` / `K` / `<leader>rn` / `<leader>ca` 等）、`vim.lsp.completion.enable`。
- 新增 `lua/plugins-config/conform.lua`：prettier / shfmt 的 filetype 映射、`lsp_format = 'fallback'`、`<leader>f`。
- 新增 `lua/plugins-config/mason.lua`：mason setup、bin 目录 `PATH` 注入、按 Node 可用性计算的 `ensure_installed`。
- 受管文件清单从 9 个扩为 12 个：同步更新 `.chezmoi.toml.tmpl` 的 `$neovimTargets`、`lib/neovim-bootstrap.sh` 的 "nine" 文案、README 的文件列表，以及相关测试断言。
- `release/managed-plugins.tsv` 新增 4 行，每行包含固定 40 位 commit 与探针文件。

### 接受的代价

- mason 下载的工具不在 Release 快照的 digest 校验范围内，只能通过固定版本号近似可复现，不提供独立签名校验。此点必须在用户文档中写明。
- 缺少 Node 时功能不完整，通过警告提示，不阻塞安装。
- pnpm 不在本次范围内。

## Testing Decisions

- 在现有 `tests/neovim-runtime.sh` 的公共 seam 上扩展：为 4 个新插件提供本地 fixture 桩，断言受管配置被加载、LSP server 与 formatter 映射被注册。
- 工具供给步在 routine 测试中必须被替换/打桩，**不得真实下载**；断言供给步被调用、且未访问网络。
- 覆盖两条降级分支：
  - 有 `node` 时，`ensure_installed` 包含全部 6 个 mason 包；
  - 无 `node` 时，`ensure_installed` 仅包含 `marksman` 与 `shfmt`，供给步退出码为 0，stderr 出现明确警告。
- 断言 `--fnm` 行为未变：`tests/fnm.sh` 与 `tests/fnm-runtime.sh` 的现有覆盖保持通过，且不出现 Node 版本安装或 pnpm 安装的调用。
- 更新 `tests/neovim.sh`、`tests/installer.sh`、`tests/combined-installation.sh` 中受管文件数量与安装步骤相关的断言。
- 可选扩展 `tests/neovim-live.sh` 的 smoke，但不得让它成为 routine 依赖。
- 断言 `<leader>f` 已绑定，且不存在保存时自动格式化的 autocmd。

## Out of Scope

- 让 `--fnm` 自动安装 Node 版本或 pnpm。
- 使用 nvim-cmp / LuaSnip 等多源补全；本次只用内置 `vim.lsp.completion`。
- 保存时自动格式化、项目级 formatter 配置发现（如 `.prettierrc` 之外的复杂解析）。
- 把语言服务器/formatter 二进制纳入 Release 快照或做独立签名校验。
- Treesitter 高亮、DAP、lint 集成、Python/Go/Rust/Lua 等其他语言。
- 修改 mason 之外的插件供给机制，或改变已发布 Release 的历史行为。

## Further Notes

- 本 spec 记录 2026-09-22 与 Owner 的决策对话结果：供给机制选 mason、挂载点并入 `--neovim`、`--fnm` 保持现状、无 Node 时只警告并跳过、接受 mason 不做独立签名校验。
- Neovim 基线 `0.12.5` 已提供 `vim.lsp.config` / `vim.lsp.enable` / `vim.lsp.completion`，因此不需要更重的补全或 LSP 框架。
- 现有的"恢复快照 → 应用配置 → runtime readiness"顺序保持不变，供给步插入在配置应用之后、readiness 检查之前或并行合适位置。
- 实现完成后需要一次新的 Base Dotfiles Release，才能让发布版安装带上新的插件快照与配置。

## Implementation

Implemented locally on branch `feat/neovim-lsp-format` (no-PR mode). The tracer bullets live in `.scratch/neovim-lsp-format/issues/`:

- `01-managed-plugins-and-file-manifest` — managed plugin snapshot rows and the 9 → 12 file manifest.
- `02-markdown-lsp-end-to-end` — marksman LSP, builder/mason wiring, the installer supply step and the Node-free degradation.
- `03-shell-formatting-end-to-end` — conform.nvim with shfmt and manual `<leader>f` formatting.
- `04-node-resolution-and-degradation` — fnm-aware Node resolution and deterministic degradation.
- `05-node-dependent-lsp-and-prettier` — ts_ls/bashls/jsonls plus prettier mappings.
- `06-docs-and-verification` — README capability matrix, Preview copy and full-suite verification.

A new Base Dotfiles Release is still required before a released install can carry the new plugin snapshot and configuration.

Reconciliations made while implementing:

- **Tool count.** "6 个工具" counts capability classes. `ensure_installed` holds exactly six mason packages: the Node-free `marksman` and `shfmt`, plus the Node-dependent `typescript-language-server`, `bash-language-server`, `json-lsp` and `prettier`. `typescript`/tsserver is no longer listed separately because `typescript-language-server` pulls it in through its registry `extra_packages`.
- **Package rename.** The current mason registry names the JSON server package `json-lsp` (it provides the `vscode-json-language-server` binary and the `jsonls` lspconfig server). The table above still shows its former name `vscode-langservers-extracted`.
- **Version pinning.** Each `ensure_installed` entry carries the `version` recorded in the mason registry at implementation time, which is what "只能通过固定版本号近似可复现" refers to; these artifacts remain outside the Release snapshot's digest verification.
