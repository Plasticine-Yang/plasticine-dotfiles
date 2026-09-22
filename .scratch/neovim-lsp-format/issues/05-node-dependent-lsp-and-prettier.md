# 05: Node 依赖的 LSP 与 prettier 端到端

**What to build:** 交付剩余语言的完整纵切：当 Workstation 具备 Node 工具链时，执行 `--neovim` 后 javascript、typescript、shell、json 的 LSP 与 javascript、typescript、json、markdown 的格式化全部自动就位。

**Blocked by:** 03, 04.

**Status:** ready-for-agent

- [ ] 有 Node 时 `ensure_installed` 包含 `typescript-language-server`、`typescript`、`bash-language-server`、`vscode-langservers-extracted`、`prettier`。
- [ ] LSP 配置启用 `ts_ls`、`bashls`、`jsonls`，并保留 02 中的 `marksman`。
- [ ] 格式化配置把 `prettier` 映射到 javascript、typescript、json、markdown 相关 filetype。
- [ ] 集成测试以"Node 可用"的受控场景断言 6 个工具都被请求安装、相应 server 已启用、formatter 映射完整。
- [ ] 无 Node 场景下这些工具被跳过且不影响 02、03 已交付的 Markdown LSP 与 shell 格式化。
- [ ] `--fnm` 行为保持不变：不安装 Node 版本、不安装 pnpm，`tests/fnm.sh` 与 `tests/fnm-runtime.sh` 现有覆盖保持通过。
