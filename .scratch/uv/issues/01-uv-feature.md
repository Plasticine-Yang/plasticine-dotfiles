# 增加独立 uv Feature

Status: done
Type: task
Blocked by:

## 验收条件

- CLI、交互选择、预览、chezmoi apply 和 Release source 包含 uv Feature，且与现有 Feature 任意组合、顺序无关。
- 缺失时通过官方安装器把 uv/uvx 安装到 `~/.local/bin`；安装器收到 `UV_INSTALL_DIR` 与 `UV_NO_MODIFY_PATH=1`，macOS 上归档校验通过 shim 真正执行，并写入可自更新的 receipt。
- 健康受管安装走 `uv self update`；uvx 缺失、receipt 缺失或前缀不符走安装器修复；不降级、不遮蔽。
- 外部归属、损坏/预发布/无法解析版本、符号链接目标、下载或自更新失败明确停止；配置不应用，可修复后重跑。
- 取消、dry-run、未选择不联网、不写 uv 状态；单选 uv 不改任何 shell 文件，交互启动不执行 uv。
- 除 `~/.local/bin/uv`、`~/.local/bin/uvx` 外不写受管文件；Python、tool、cache 和项目环境保持 uv 原生状态。
- 通过相关 `scripts/check.sh` 套件（uv、uv-runtime、integration、combined-installation、cli、workflows、release 等），并更新 CI 与 README。

## Comments

2026-10-19：用户确认采用官方安装器 + `uv self update`，范围只维护 uv/uvx，并直接实施。

2026-10-19：实现完成。新增独立 `--uv`、交互选择、官方安装器 + `uv self update` 路线、receipt 前缀校验与安装器修复、外部归属/损坏/预发布停止、macOS `sha256sum` shim，并接入组合 prepare、CI 与 README。

验证：`scripts/check.sh uv uv-runtime integration combined-installation cli workflows installer diff-config release release-payload` 全部通过；在一次性 HOME 中执行真实上游安装器与自更新 smoke，安装 0.13.1，receipt 前缀正确且未写 `.zshrc`/`.profile`，自更新走已安装 receipt。另修正 `diff-config` 交互测试在菜单增加一项后确认字节被终端 teardown 吞掉的竞态，发送确认前增加短暂等待。
