# 01: 拆分基础环境并修复非交互 Node 查找

Status: done

按 [spec](../spec.md) 实现基础环境、交互配置、启动文件集成和运行时测试，
整理本机重复 compinit 与 Go PATH。验证通过后用中文提交。

## 验证

运行 shell、shell-runtime、shell-environment-runtime、fnm-runtime、integration、
combined-installation、installer、lazygit、fnm 和 workflow 等相关脚本。

## 完成记录

- 已实现 `.zshenv` / `.zprofile` 的基础环境区块与交互配置拆分，保留
  已选 Node，并验证 fnm 父子会话隔离和 Owner 登录配置优先级。
- 11 个相关套件通过：shell（327 秒）、shell-runtime、
  shell-environment-runtime、fnm-runtime、integration、combined-installation、
  installer、lazygit、fnm、workflows、release-payload；ShellCheck、Zsh
  语法检查与 diff 检查通过。
- 新增两个启动文件后，综合安装矩阵超过原 300 秒上限；CI 保留超时
  保护并将 Shell 综合套件上限调整为 420 秒。
- 本机配置已经应用，重复 compinit 和 Go 启动调用已移除，个人 Devflow
  PATH 已迁至 `.zshenv`。原配置保存在私有 shell-environment 备份目录。
  四种真实启动模式均可找到 Node / fnm，stderr 为空。

## Comments

发布准备时合入远端 v0.5.0 的 main，保留 Rust 与自定义 CARGO_HOME 支持，
将 Cargo PATH 一并移至基础环境层，并接入 scripts/check.sh。通过隔离入口
重新验证 workflows、check-runner、shell-environment-runtime、shell-runtime、
fnm-runtime、rust-runtime、integration、combined-installation、rust、self-update
（含 Bash）、ci-gate 和 release-payload。新增非交互自定义 Cargo home 验证。
