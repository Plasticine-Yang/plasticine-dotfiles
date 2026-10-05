# Rust 环境管理

新增独立的 `rust` Feature，交互菜单和 `plasticine -y --rust` 均可选择，支持 macOS/Linux，与已有 Feature 任意组合。

采用官方 rustup 安装器和原生 self update。确认 apply 后安装或更新 stable，并保证 Cargo、rustfmt、Clippy 可运行；首次安装以 stable 为默认。已有默认工具链（包括显式 none）、nightly、其他版本、项目覆盖和 Cargo 配置保持原有选择。尊重绝对路径的 CARGO_HOME/RUSTUP_HOME，不接管外部包管理器安装或遮蔽已有系统 Rust。

单选 Rust 不改 shell 文件；共享 Zsh 配置在原生 Cargo bin 目录存在时接入 PATH，保留自定义 CARGO_HOME。预览只做本地观测，取消、dry-run、未选择不查询上游或修改 Rust 状态。原生维护失败返回非零，保留已完成的原生效果供重试；全部选中工具准备成功后才应用配置。

验证通过公开 chezmoi/install.sh 入口的受控安装集成、真实 Zsh 运行时、组合安装、CLI 与 Release 检查，不新增 UI 单元测试。

官方依据：[安装](https://rust-lang.github.io/rustup/installation/index.html)、[环境变量](https://rust-lang.github.io/rustup/environment-variables.html)、[原生命令及默认工具链行为](https://github.com/rust-lang/rustup/blob/main/src/cli/rustup_mode.rs)。
