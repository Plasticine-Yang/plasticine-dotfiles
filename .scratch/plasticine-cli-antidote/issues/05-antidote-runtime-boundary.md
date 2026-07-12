# 05 — 保护 Antidote Tool-managed State 边界

**What to build:** Reconciliation 明确把 Antidote 的插件 clone、静态 bundle、snapshots、compinit dumps 和编译产物保持为 Tool-managed State，不进入 Plan、Apply、Backup、Retirement、Doctor ownership 语义。

**Blocked by:** 04 — 物化 Zsh 插件声明与 Antidote bootstrap

**Status:** ready-for-agent

- [ ] Antidote runtime root 统一位于 `~/.plasticine/runtime/antidote` 下，包含 plugin home、static bundle、snapshots、compinit dumps、compiled files 和 update logs。
- [ ] Plan 不读取 Antidote plugin clone 目录、generated static bundle、snapshots、`.zcompdump` 或 `.zwc` 内容。
- [ ] Apply 不创建、修改、删除、备份或版本化 Antidote runtime state；Zsh startup 产生的 runtime 内容保持原样。
- [ ] Backup 只覆盖被 adoption/Owner drift 影响的 managed paths，不备份 Antidote plugin runtime。
- [ ] Retirement 永不删除 Antidote runtime state，即使 Antidote Managed Tool 或 shell bootstrap 在未来 Release 中被移除。
- [ ] Doctor 验证 Antidote core payload、stable source shim、managed plugin declaration 和 bootstrap relocation；受管效果缺失或 drift 时 unhealthy。
- [ ] Doctor 不枚举、运行、更新、修复或报告 Antidote plugin clone/generated files 的内容；最多报告受管 bootstrap 是否指向正确 runtime root。
- [ ] Reconciler-level tests 人工放置 runtime files 后，证明 Plan/Apply/Doctor/Retirement/Backup 都不观察或改变这些文件。
