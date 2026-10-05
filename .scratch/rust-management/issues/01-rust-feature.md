# 增加独立 Rust 环境管理

Status: done
Type: task
Blocked by:

## 验收条件

- CLI、交互选择、预览、chezmoi apply 和 Release source 包含 Rust Feature。
- 新安装有 stable、Cargo、rustfmt、Clippy；重跑维护 rustup/stable，保留已有默认工具链、项目配置和自定义 homes。
- 外部归属、损坏目标、失败下载和原生维护失败明确停止；取消、dry-run、未选择不产生 Rust 维护。
- shell 接入 Cargo PATH，经真实 Zsh 验证缺失目录、自定义目录、重复加载和后续 Owner 内容。
- 通过相关 scripts/check.sh 套件，并提交实现、文档和完成记录。

## Comments

用户已确认按完整 Rust 环境方案实施。

2026-10-05：实现完成。新增独立 --rust、官方 rustup bootstrap/native update 和明确的 stable 组件维护；保留已有默认工具链与自定义 homes，接入共享 Cargo PATH。交互、组合准备顺序、dry-run、取消、重试和 Release source 已接入。

验证：通过 scripts/check.sh 的 rust、rust-runtime、integration、workflows、combined-installation、cli、release、shell-runtime、fnm-runtime、installer、diff-config、shell、check-runner 共 13 个相关 suite；integration 同时检查生产模块、渲染脚本和测试脚本的 ShellCheck/语法。git diff --check 通过。Rust 上游行为通过受控安装器和原生命令 fixture 验证，Zsh 使用真实运行时；未在用户 HOME 中安装工具或运行 live Rust 下载。
