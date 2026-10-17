# 08: 发布 v0.5.3

Status: done
Blocked by: 06, 07

用户授权在 fnm 激活收敛与 apply 冲突诊断完成后发布 patch release。
发布前最新稳定版本为 v0.5.2。

## 验收

- 推送最终代码，并让该 commit 通过四个必需 CI job。
- 从 `main` 手动触发 Release workflow，发布 v0.5.3。
- 核验 tag、target commit、最新稳定标记、五个附件与 digest。
- 记录发布链接、CI / Release run 与独立核验结果。

## Comments

2026-10-17 完成发布与核验：

- [v0.5.3](https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/tag/v0.5.3)
  已发布为最新稳定版本（immutable）。tag 与 target commit 均为
  `5415b6819dae655ea98b1d870653aebc221b0617`。
- [CI](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39031230848)
  第一次运行在 `Test (ubuntu-24.04)` 的 `diff-config` 上超时：该套件的
  `expect` 交互确认对 pty 时序敏感，`expect eof` 挂到 180 秒上限；
  其余三个 job 通过。仅重跑失败 job 后通过，整轮结论为 success，
  `require-ci-success` 复核通过。这是既有的交互式测试 flake，与本次
  改动无关（改动只落在 apply 失败分支，在确认提示之后）。
- [Release](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39032013242)
  的精确提交门禁、构建、draft 附件校验与发布全部成功（23 秒）。
- 独立核验 `releases/latest` 指向 v0.5.3，tag SHA 与 target commit 一致，
  `isDraft=false`、`isImmutable=true`；五个附件名正确，GitHub digest 与
  `SHA256SUMS` 逐项一致，下载后 `shasum -a 256 -c` 全部通过。
- `scripts/verify-release.sh` 通过：installer 固定到 `5415b68`/v0.5.3、
  source bundle 的 HEAD 为该 commit 且 detached，一次性 HOME 的安装 smoke
  得到健康的 `plasticine v0.5.3`。
- 本机（macOS）未执行 `plasticine self-update`。

## 待跟进

- 受影响的 Linux 机器需先 `self-update`，再跑 `plasticine -y --shell`；
  该机器上 `~/.plasticine/zsh/shared.zsh` 仍被标记为 `MM` 冲突，apply 会被
  拒绝，但 v0.5.3 会打印冲突路径与恢复提示，之后用强制 apply 覆盖即可。
- `tests/diff-config.sh` 的 expect 交互路径建议单独加固，避免再次触发
  必需检查超时。
