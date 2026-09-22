# 06: 文档与整体验收

**What to build:** 把已交付能力写进 Owner 可读的用户文档，并完成整体验收，使 Base Dotfiles 的发布说明、Preview 文案与实际行为一致。

**Blocked by:** 05.

**Status:** done

- [ ] README 描述五门语言的能力矩阵、`<leader>f` 手动格式化、缺少 Node 时的降级行为与补齐指引。
- [ ] README 明确 mason 下载的工具不在 Release 快照的独立签名/digest 校验范围内，只能靠固定版本号近似可复现。
- [ ] 安装器 Preview 文案反映新增的工具供给步骤与 `--neovim` 的 Node 依赖关系。
- [ ] README 说明 `--fnm` 行为未变，以及 Node/pnpm 不在 `--neovim` 内自动安装。
- [ ] spec 与 implementation ticket 之间可交叉引用，实现完成后需要一次新的 Base Dotfiles Release 才能让发布版安装生效。
- [ ] 全部相关测试套件（neovim、neovim-runtime、installer、combined-installation、fnm）通过，确认没有引入联网依赖或对 `--fnm` 的意外改动。

## Comments

2026-09-23: Implemented on `feat/neovim-lsp-format` in commit 42f428d.

- README 新增「LSP 与格式化」小节：五门语言能力矩阵、`<leader>f` 手动格式化与 LSP fallback、缺少 Node 的降级与补齐指引、mason 工具不在 Release 独立签名/digest 范围内、`--fnm` 行为未变且 Node/pnpm 不在 `--neovim` 内自动安装。
- `lib/neovim-bootstrap.sh` 的 Preview 增加工具供给与 Node 依赖说明；`spec.md` 增加实现与 01–06 ticket 的交叉引用。
- 整体验收：`tests/neovim-runtime.sh`、`tests/neovim.sh`、`tests/installer.sh`、`tests/combined-installation.sh`、`tests/fnm.sh`、`tests/fnm-runtime.sh` 全部通过；`scripts/build-managed-plugins.sh` 对新清单构建快照成功（neovim 行 13 条，4 个新插件目录齐全）；`shellcheck` 与 `git diff --check` 干净。
