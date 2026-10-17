# 05: 发布 v0.5.2

Status: done
Blocked by: 04

用户授权发布 patch release。发布前最新稳定版本为 v0.5.1；本次带上
“交互式 fnm 优先、保证 `fnm use` 可用”的修复。

## 验收

- 推送最终代码，并让该 commit 通过四个必需 CI job。
- 从 `main` 手动触发 Release workflow，发布 v0.5.2。
- 核验 tag、target commit、最新稳定标记、五个附件与 digest。
- 记录发布链接、CI / Release run 与独立核验结果。

## Comments

2026-10-17 完成发布与核验：

- [v0.5.2](https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/tag/v0.5.2)
  已发布为最新稳定版本（immutable）。tag 与 target commit 均为
  `0572bc15396e3f11c2560cbee48d2c5ff1919d9f`。
- [CI](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39021253102)
  的 Ubuntu、macOS、Debian x86_64 / arm64 四个必需 job 全部成功；
  [Release](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39021606060)
  的精确提交门禁、构建、draft 附件校验与发布全部成功（17 秒）。
- 独立核验 `releases/latest` 指向 v0.5.2，tag SHA 与 target commit 一致，
  `isDraft=false`、`isImmutable=true`；五个附件名正确，GitHub digest 与
  `SHA256SUMS` 逐项一致，下载后 `shasum -a 256 -c` 全部通过。
- `scripts/verify-release.sh` 通过：installer 固定到 `0572bc1`/v0.5.2、
  source bundle 的 HEAD 为该 commit 且 detached，一次性 HOME 的安装 smoke
  得到健康的 `plasticine v0.5.2`。
- 本机（macOS）未执行 `plasticine self-update`；Linux 机器按需在发布后
  自行升级并应用 `--shell`。
