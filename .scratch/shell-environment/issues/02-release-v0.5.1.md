# 02: 发布 v0.5.1 并验证本机升级

Status: done
Blocked by: 01, 03

用户已授权发布并升级本机。远端最新稳定版本为 v0.5.0；将本次基础环境
修复合入最新 main，保留 Rust / CARGO_HOME 支持及隔离测试入口。

## 验收

- 合入后通过相关本地检查，并推送最终代码。
- 该提交通过四个必需 CI job，Release workflow 的精确提交门禁通过。
- 发布 v0.5.1，核验 tag、五个附件和 digest，确认为最新稳定版本。
- 本机升级 plasticine 并应用 shell，验证四种启动模式和 Node 继承。
- 记录发布链接、CI / Release run、本机结果和最终状态。

## Comments

2026-10-12 完成发布与本机升级：

- [v0.5.1](https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/tag/v0.5.1)
  已发布为最新稳定版本。tag 与 target commit 均为
  `c53ce53ac352d277b2e95fcd3fc08a094e7da0d2`。
- [CI](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/38243259599)
  的 Ubuntu、macOS、Debian x86_64 / arm64 四个 job 全部成功；
  [Release](https://github.com/Plasticine-Yang/plasticine-dotfiles/actions/runs/38243261699)
  的精确提交门禁、构建、附件校验和发布全部成功。
- 独立核验正式 Release、latest 和 tag SHA，五个附件名与 GitHub digest
  正确；下载 SHA256SUMS 与 install.sh，核验附件 digest，并将四个 payload
  的 GitHub digest 与 SHA256SUMS 逐项比对。
- 本机 `plasticine self-update` 从 v0.3.1 升级到 v0.5.1；随后
  `plasticine -y --shell` 成功，已部署基础环境与共享配置和该版本 source
  完全一致，source 工作区干净。再次 self-update 确认为最新版本。
- 首次应用因六个现有插件缓存的 origin 缺少 `.git` 后缀而被严格校验
  拒绝。备份 Git 配置后，仅将等价 HTTPS 仓库地址规范化；逐项验证
  HEAD 与工作文件未变，重试成功。备份位于
  `~/.plasticine/backups/plugin-origins-v0.5.1-tmvpa0r8/`。
- 真实 Zsh 的 `-c`、`-lc`、`-ic`、`-lic` 均能运行 Node v24.18.0、
  查找 fnm，并包含 local / Go PATH，stderr 为空。四种模式均保留入口
  已选 Node；真实 fnm 父子会话独立且版本保持一致。默认 Node alias
  未改变，`.zshenv` 原有 0600 权限保留。
