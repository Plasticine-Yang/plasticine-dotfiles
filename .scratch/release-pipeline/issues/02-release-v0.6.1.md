# 02: 发布 v0.6.1 patch release

Status: done

用户请求发布 patch release。发布前最新稳定版本为 v0.6.0
（tag `b6d1551`）。v0.6.0 之后 `main` 上只有测试稳定性修复、release
skill 与文档记录，没有 Feature 或用户可选行为变化，因此按 patch bump
发布 v0.6.1；这也收尾了 v0.5.3 遗留的 `diff-config` 交互测试 flake
加固项。

## 验收

- 从干净的 `main` 手动触发 Release workflow，精确 commit 通过四个必需
  CI job。
- 发布 v0.6.1，并核验 tag、target commit、latest/immutable、五个附件与
  digest。
- 用发布版安装器在一次性 HOME 中验证安装与重跑路线，且不产生 shell
  启动文件副作用。
- 记录发布链接、CI / Release run 与独立核验结果。

## Comments

2026-10-19 完成发布与核验：

- [v0.6.1](https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/tag/v0.6.1)
  已发布：`isDraft=false`、`isImmutable=true`、`isPrerelease=false`，
  `releases/latest` 指向该版本。tag 与 target commit 均为
  `6fdeabd163090228d6569050b14c8f6fc5cec2b3`。
- 该 commit 的 [CI run 39235264360](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39235264360)
  四个 job 全部成功（`Test (ubuntu-24.04)`、`Test (macos-14)`、
  `Debian 12 shell (ubuntu-24.04)`、`Debian 12 shell (ubuntu-24.04-arm)`）。
- [Release run 39236207408](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39236207408)
  在 29 秒内通过请求校验、CI 复用、资产构建、draft 创建与附件校验后发布。
- 五个附件名为 `install.sh`、`plasticine-cli.tar.gz`、
  `plasticine-managed-plugins.tar.gz`、`plasticine-source.bundle`、
  `SHA256SUMS`；GitHub 记录的 sha256 与 `SHA256SUMS` 逐项一致，下载后
  `shasum -a 256 -c SHA256SUMS` 全部通过。
- 发布版 `install.sh` 内嵌 `v0.6.1` 与 `6fdeabd`，`--help` 暴露 `--uv`；
  source bundle 的 HEAD 为该 commit（detached），包含
  `lib/uv-bootstrap.sh`、`tests/uv.sh`、`tests/uv-runtime.sh`、
  `tests/check-runner.sh` 与 `.agents/skills/release`。
- 一次性 HOME 中执行 `sh install.sh -y --uv`：首次 `uv: route=install`，
  安装 uv/uvx `0.13.1`，receipt 前缀指向该 HOME 的 `.local/bin`；重跑为
  `uv: route=self-update`，报告已是 `v0.13.1`。两次 HOME 顶层都只有
  `.cache`、`.config`、`.local`，没有 `.zshrc`、`.zprofile`、`.bashrc`
  等 shell 启动文件副作用；安装后的 `plasticine v0.6.1` 健康。
- 本次 patch 内容：`d5d58e5`（`check.sh` 用符号链接匹配 macOS CI 的
  TMPDIR 路径形状，`diff-config` 交互测试等待界面渲染并有限重试）与
  `6fdeabd`（release skill、AGENTS 与新增 Feature 文档）。已核实的本地
  `scripts/check.sh` 结果不替代发布门禁。
