# 发布包含 uv Feature 的 Release

Status: done
Type: task
Blocked by: 01

## 验收条件

- 实现与文档提交到 `main` 后，精确 commit 通过四个必需 CI job。
- 通过现有 Release workflow 发布新的稳定版本，Release 附件包含新的 source bundle。
- 本机用发布版安装器验证 `plasticine -y --uv`：安装 uv/uvx、重跑走自更新、预览与取消无副作用。

## Comments

需要新的 Base Dotfiles Release，发布版安装器才会带上该 Feature；本地实现和测试不代替发布验证。

2026-10-19：已发布 [v0.6.0](https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/tag/v0.6.0)，为 latest、immutable，tag 指向 `b6d15516092726128f21d7ffa4e2a418f95aa4b9`。[CI Run 49](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39223705722) 的四个 job 全部成功；[Release run 39227015770](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39227015770) 通过请求校验、CI 复用、资产构建、draft 创建与附件校验后发布。

本机核验：五个附件的 SHA-256 全部通过；发布版 `install.sh` 内嵌 `v0.6.0` 与 `b6d1551`，`--help` 暴露 `--uv`；source bundle 包含 `lib/uv-bootstrap.sh` 与 `tests/uv.sh`，其 HEAD 为同一 commit。
