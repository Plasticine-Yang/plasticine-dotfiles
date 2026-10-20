# 03: 发布 v0.6.2 patch release

Status: done

用户请求在 uv PATH helper 修复完成后发布 patch release。发布前最新稳定版本为
v0.6.1（tag `6fdeabd`）；本次 `main` 上只有 `365bfcd` 的修复与随之更新的文档、
测试，没有 Feature 或用户可选行为变化，因此按 patch bump 发布 v0.6.2。

## 验收

- 从干净的 `main` 手动触发 Release workflow，精确 commit 通过四个必需 CI job。
- 发布 v0.6.2，并核验 tag、target commit、latest/immutable、五个附件与 digest。
- 用发布版安装器在一次性 HOME 中验证安装与重跑路线，确认 uv PATH helper 会被
  还原成 source-only 形态，且不产生 shell 启动文件副作用。
- 记录发布链接、CI / Release run 与独立核验结果。

## Comments

2026-10-20 完成发布与核验：

- [v0.6.2](https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/tag/v0.6.2)
  已发布：`isDraft=false`、`isImmutable=true`、`isPrerelease=false`，
  `releases/latest` 指向该版本。tag 与 target commit 均为
  `365bfcd8bdd5c151ed69cb0e4865b1185a3b5ebf`。
- 该 commit 的 [CI run 39403902182](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39403902182)
  四个 job 全部成功（`Test (ubuntu-24.04)`、`Test (macos-14)`、
  `Debian 12 shell (ubuntu-24.04)`、`Debian 12 shell (ubuntu-24.04-arm)`）。
- [Release run 39403933499](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/39403933499)
  在 5 分 39 秒内通过请求校验、CI 复用、资产构建、draft 创建与附件校验后发布。
- 五个附件名为 `install.sh`、`plasticine-cli.tar.gz`、
  `plasticine-managed-plugins.tar.gz`、`plasticine-source.bundle`、
  `SHA256SUMS`；下载后 `shasum -a 256 -c SHA256SUMS` 四项全部通过。
- 发布版 `install.sh` 的 `--help` 暴露 `--uv`；source bundle 克隆后包含
  `lib/uv-bootstrap.sh` 的 `plasticine_uv_restore_path_helper` 与
  `tests/uv.sh` 的 `helper-symlink` 场景。
- 一次性 HOME 中执行 `sh install.sh -y --uv`（PATH 去掉宿主的
  `~/.local/bin`，避免外部 uv 触发停止）：首次为 `uv: route=install`，装上
  `plasticine v0.6.2`、`uv 0.13.3`、`uvx 0.13.3`，顶层没有 `.zshrc`、
  `.zshenv` 等 shell 启动文件，也没有 `~/.local/bin/env`（安装器被
  `UV_NO_MODIFY_PATH=1` 挡住，不写该 helper）。
- 之后手工造出回归形态（`~/.local/bin/env` 为 755 且带
  `exec /usr/bin/env "$@"`）并重跑：走 `uv: route=self-update`，日志报告
  `restored the source-only PATH helper`，helper 变回 `644` 且不再含 `exec`
  行。
- 本次 patch 内容：`365bfcd`（uv Feature 在安装/修复/自更新后还原 `env`
  helper 的两个不变量）。发布后另有一次文案与测试补充：上游安装器的
  `write_env_script_sh` 受 `NO_MODIFY_PATH=0` 门控，本 Feature 不会写出该
  helper，README/spec 与预览文案据此改为“更早的安装留下的文件才会被还原”。
