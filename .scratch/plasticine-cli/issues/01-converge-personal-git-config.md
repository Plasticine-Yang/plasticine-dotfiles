# 01 — 首次收敛个人 Git 配置

**What to build:** 让 Owner 能在空 Workstation 上运行最小但完整的 Plasticine CLI：先离线查看个人 Git 配置的完整 Plan，再用同一个 Apply 将配置集中物化、记录 ownership，并用 Doctor 验证健康；重复 Apply 必须稳定收敛而不产生额外变化。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] 开发构建提供且只公开 `plan`、`apply`、`doctor`、`version` 四个命令；未知命令和无效参数返回 usage error。
- [ ] CLI 直接调用一个 concrete Reconciler，Desired State 使用 typed Go 表达；不暴露 public Action DSL、用户 YAML/template/plugin 配置或 machine-local value override。
- [ ] `version` 能区分 Release 与开发构建，并在开发构建中报告 source-derived commit、dirty 状态和 Desired State digest；开发构建可正常 Plan 与 Apply。
- [ ] 在隔离的空 Workstation 上，`plan` 离线列出创建 Plasticine Home、集中式个人 Git 配置和最小 Git include shim 的完整变化，不读取网络、不改变文件系统或 Reconciliation State，且“存在变化”仍是成功结果。
- [ ] `apply` 创建 mode 0700 的 Owner-only Plasticine Home，原子物化手写个人 Git 配置，并只在约定位置创建必要的 materialized include shim；任何内容都不依赖仓库 checkout 或 Release 解压目录。
- [ ] 新 Desired State 保留已接受的个人 Git 设置，但不包含明文 credential store，也不创建可覆盖完整个人配置的本地 override fragment。
- [ ] 成功 Apply 后，Reconciliation State 记录 applied Release 或开发 Desired State digest，以及由 `git-config` Component 接受的 Managed Path ownership；实际 Workstation 内容仍是后续观察的事实来源。
- [ ] 对已收敛 Workstation 再次运行 `plan` 和 `apply` 时没有内容重写、重复副作用或 ownership 抖动。
- [ ] `doctor` 能只读报告已收敛 Git 配置健康，并在受管内容缺失或漂移时返回不健康且不尝试修复。
- [ ] Reconciler 的 Plan、Apply、Doctor 外部行为由 deterministic Adapters 覆盖，并由隔离临时 HOME 的真实文件系统测试证明权限、原子物化、state 持久化和重复 Apply。
