# 05: Node 依赖的 LSP 与 prettier 端到端

**What to build:** 交付剩余语言的完整纵切：当 Workstation 具备 Node 工具链时，执行 `--neovim` 后 javascript、typescript、shell、json 的 LSP 与 javascript、typescript、json、markdown 的格式化全部自动就位。

**Blocked by:** 03, 04.

**Status:** done

- [ ] 有 Node 时 `ensure_installed` 包含 `typescript-language-server`、`typescript`、`bash-language-server`、`vscode-langservers-extracted`、`prettier`。
- [ ] LSP 配置启用 `ts_ls`、`bashls`、`jsonls`，并保留 02 中的 `marksman`。
- [ ] 格式化配置把 `prettier` 映射到 javascript、typescript、json、markdown 相关 filetype。
- [ ] 集成测试以"Node 可用"的受控场景断言 6 个工具都被请求安装、相应 server 已启用、formatter 映射完整。
- [ ] 无 Node 场景下这些工具被跳过且不影响 02、03 已交付的 Markdown LSP 与 shell 格式化。
- [ ] `--fnm` 行为保持不变：不安装 Node 版本、不安装 pnpm，`tests/fnm.sh` 与 `tests/fnm-runtime.sh` 现有覆盖保持通过。

## Comments

2026-09-23: Implemented on `feat/neovim-lsp-format` in commit b3ff226.

- `lua/plugins-config/mason.lua`：有 Node 时 `ensure_installed` 追加 `typescript-language-server`、`typescript`、`bash-language-server`、`vscode-langservers-extracted`、`prettier`（加上 Node-free 的 `marksman`/`shfmt` 共 7 个 mason 包，对应 capability 表里的 6 类工具，其中 `typescript` 随 `typescript-language-server` 提供 tsserver）。
- `lua/plugins-config/lsp.lua`：servers 扩为 `marksman`、`ts_ls`、`bashls`、`jsonls`，统一经 `vim.lsp.enable` 启用。
- `lua/plugins-config/conform.lua`：`prettier` 映射到 javascript/javascriptreact/typescript/typescriptreact/json/jsonc/markdown，保留 shfmt 的 shell 映射。
- `tests/neovim-runtime.sh`：以本套件自有的 PATH 分两轮运行，断言无 Node 时清单恰为 `{marksman, shfmt}`，有 Node 时包含全部 Node 依赖包，并校验 server 启用与 formatter 映射完整。
- `--fnm` 未改动；`tests/fnm.sh`、`tests/fnm-runtime.sh` 保持通过。

2026-09-23 (code review follow-up, commit 29af652): 现行 mason registry 中
`vscode-langservers-extracted` 已更名为 `json-lsp`（仍提供
`vscode-json-language-server`），`typescript` 也不再是独立包，而由
`typescript-language-server` 的 `extra_packages` 自动附带。因此 Node 依赖清单
修正为 `typescript-language-server`、`bash-language-server`、`json-lsp`、
`prettier` 四项，与 spec 的“6 个工具 / 跳过 4 项”完全一致。每个条目现在都
固定了版本号（见 `mason.lua`）。运行时测试相应更新，并新增 node-without-npm
边界断言。
