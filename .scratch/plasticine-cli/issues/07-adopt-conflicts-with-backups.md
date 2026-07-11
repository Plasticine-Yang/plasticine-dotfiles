# 07 — 显式接管 Conflict 并保留 Backup

**What to build:** 让 Owner 面对未受管内容、Managed Path 上的 Owner drift 或丢失 state 时，先在完整 Plan 中看到全部 Conflict；只有显式 `--adopt` 后 Plasticine 才能为有风险的人类内容创建唯一 Backup 并继续收敛，Secret 永远不能被接管或复制。

**Blocked by:** 04 — 恢复中断的 Component Apply；05 — 持久化 Workstation Scope 与 Suspension；06 — 安全迁移并验证 Reconciliation State

**Status:** implemented

- [x] 未受管路径上的不同内容、continuing Managed Path 上不匹配最后 accepted digest 的 Owner drift，以及 state 丢失后已存在的候选 Managed Path 都成为 Conflict；即使丢失 state 后字节恰好相等也不得猜测 ownership。
- [x] Plan 一次列出当前 Scope 与 `--component` filter 内的全部 adoptable 和 non-adoptable Conflicts，不修改现场，也不在输出或日志中暴露原始内容。
- [x] 没有 `--adopt` 时任何 Conflict 都阻塞相关 mutation；`--adopt` 一次授权 filtered Plan 中的所有 adoptable Conflicts，不提供 per-path adoption 语言。
- [x] 非交互式 adoption 同时要求 `--adopt` 与 `--yes`；若 Plan 还包含 System Change，仍独立要求 `--allow-system`，任一授权缺失都不会先创建 Backup 或写 ownership。
- [x] 每次 adoption 或覆盖 Owner drift 都在破坏性 mutation 之前创建 Owner-only、唯一且不会被后续运行覆盖的 Backup，并记录足以手工识别来源的非敏感 metadata；不使用固定 `.bak` 文件。
- [x] Backup byte-for-byte 保留 opaque 原内容，长期保留且不自动 prune；Plan、普通输出、日志和错误消息不回显 Backup payload。
- [x] 初始 CLI 不提供 Backup restore 或 prune 命令；Owner 只通过普通文件操作手工恢复或删除 Backup。
- [x] 当前内容仍匹配最后 accepted digest 的普通 Desired State 更新不创建 Backup；成功 adoption 后的重复 Apply 也不生成重复 Backup 或重复 mutation。
- [x] Secret 与 Secret Reference target 始终 non-adoptable，绝不被读取进 Backup、复制到 Plasticine Home 或写入 Plan、journal、state 和日志。
- [x] failure-injection tests 证明 Backup durable 后才允许 replacement 与 ownership commit；中断恢复不会丢失原内容、覆盖既有 Backup 或把未完成接管记为成功。
