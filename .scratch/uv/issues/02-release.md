# 发布包含 uv Feature 的 Release

Status: ready-for-human
Type: task
Blocked by: 01

## 验收条件

- 实现与文档提交到 `main` 后，精确 commit 通过四个必需 CI job。
- 通过现有 Release workflow 发布新的稳定版本，Release 附件包含新的 source bundle。
- 本机用发布版安装器验证 `plasticine -y --uv`：安装 uv/uvx、重跑走自更新、预览与取消无副作用。

## Comments

需要新的 Base Dotfiles Release，发布版安装器才会带上该 Feature；本地实现和测试不代替发布验证。
