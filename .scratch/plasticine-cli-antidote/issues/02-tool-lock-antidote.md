# 02 — 将 Antidote 加入 Tool Lock

**What to build:** Release 通过 Tool Lock 固定 Antidote 本体的 source archive、版本和 SHA-256，并让 release validation 像验证 Neovim、Lazygit、fnm、uv 一样验证 Antidote。

**Blocked by:** 01 — 支持 Managed Tool 目录 payload

**Status:** ready-for-agent

- [ ] `release.ManagedTool` 增加稳定枚举值 `antidote`，并纳入 Tool Lock completeness validation。
- [ ] `tool-lock.json` 为四个 Artifact Target 声明 Antidote 的不可变 source archive URL、artifact type、version 和 SHA-256；source-only archive 可在四个 target 重用同一 bytes。
- [ ] Tool Lock validation 仍拒绝 missing target、mutable URL、非法 artifact type 和非法 SHA-256。
- [ ] Antidote artifact metadata 不依赖 Homebrew、AUR、Nix、git clone latest、branch、installer script 或运行时 tag resolution。
- [ ] Antidote payload 要求 archive 中存在 `antidote.zsh` 与 `functions/`，否则 Plan/Apply 失败为明确的 Antidote Component/Managed Tool 错误。
- [ ] Existing Managed Tool tests 保持绿色，证明新增 Antidote 不改变 Neovim、Lazygit、fnm、uv 的 artifact selection 和 validation。
- [ ] Release validation 与 `scripts/validate-release.sh` 覆盖 Antidote Tool Lock completeness。
- [ ] 文档或 test fixture 说明 Antidote 作为 source archive Managed Tool 的原因：本体可固定，插件 ecosystem 不纳入 Tool Lock。
