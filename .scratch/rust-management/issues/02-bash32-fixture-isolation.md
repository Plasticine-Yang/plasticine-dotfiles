# 隔离 Rust 测试中的场景环境变量

Status: done
Type: task
Blocked by: 01

## 验收条件

- 自定义 homes、平台和预期失败的临时环境变量不影响后续场景。
- 原始 Rust 集成测试及真实 Zsh 测试在 Bash 3.2 POSIX 模式下通过。
- scripts/check.sh 的 rust、rust-runtime、integration 通过。

## Comments

2026-10-05：v0.5.0 发布门禁的 macOS CI 暴露测试场景污染。Bash 3.2 POSIX 模式保留函数调用前的变量赋值，导致自定义 CARGO_HOME/RUSTUP_HOME 泄漏到后续平台场景；失败注入变量也存在同一问题。在本地 Bash 3.2 复现原始失败，并用最小函数调用证明变量保留行为。将带临时环境变量的函数调用置于子 shell 后，原始 rust.sh 和 rust-runtime.sh 均通过；scripts/check.sh rust rust-runtime integration 通过。修改仅涉及测试隔离，Rust 安装逻辑不变。
