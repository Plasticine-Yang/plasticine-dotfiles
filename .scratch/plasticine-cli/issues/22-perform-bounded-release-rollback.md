# 22 — 执行有边界的旧 Release rollback

**What to build:** 让 Owner 能显式选择兼容的旧 Release，并通过正常的 Plan、Conflict 与 Retirement 规则收敛受管配置和精确 Managed Tools，而不会假称恢复整个 Workstation。

**Blocked by:** 09 — 通过最小 POSIX Bootstrap 安装 Candidate；21 — 显式 Retirement 已移除的受管资源

**Status:** ready-for-agent

- [x] 选择精确的旧 Release 时，在替换已安装 CLI 前执行 read-only compatibility check。
- [x] Compatibility check 同时覆盖 Reconciliation State schema 与所有未解决的 pending journal representation。
- [x] state 或 pending operation 不兼容时，保留当前已安装 CLI，且不执行任何 Reconciliation mutation。
- [x] 兼容的旧 Release 在 Plan 中展示其嵌入式受管配置与精确 Tool Lock 版本的恢复。
- [x] 仅由较新 Release 引入的资源使用与其他 catalog removal 相同且可见的 Retirement 规则。
- [x] rollback 中遇到的 Owner drift 仍为 Conflict，并要求与向前 Reconciliation 相同的 adoption 与 Backup 授权。
- [x] rollback 永不降级、卸载 System Dependencies，也不把它们表示为已恢复。
- [x] Tool-managed State 保持观察到的版本和内容，且永不被表示为已由 rollback 恢复。
- [x] candidate replacement 原子成功后，即使首次 Apply 被拒绝、部分成功或失败，选定的旧 CLI 仍保持已安装。
- [x] 后续 Apply 能从观察到的 Workstation state 安全续跑部分完成的兼容 rollback。
- [x] 输出清楚区分 CLI replacement、受管配置变化、Managed Tool 版本变化、Retirement、blockers 和 untouched state。
- [x] rollback 不承诺 global transaction，也不尝试对 package managers 或外部系统执行 compensating rollback。
- [x] Integration tests 使用至少两个不可变 Release fixtures，覆盖 forward state、兼容 rollback、不兼容 rollback、drift、tool downgrade、Retirement 和重复执行。
