# 04 — 为失败输出提供 next-action 指引

**What to build:** 当命令失败或被阻塞时，CLI 输出清楚展示主要原因和下一步建议，让 Owner 知道该调整命令、修复状态还是完成外部动作。

**Blocked by:** 01 — 建立 CLI Result renderer seam；03 — 优化 Plan 和 Apply 摘要输出

**Status:** ready-for-agent

- [ ] `OutcomeDenied` 输出建议交互确认或使用 `--yes`，但不暗示 bypass 风险。
- [ ] adoptable Conflict 输出建议审查 path 后使用 `--adopt`；non-adoptable Conflict 输出建议人工修复 marker/secret 等问题。
- [ ] System Change authorization blocker 输出建议审查 system changes 后使用 `--allow-system`。
- [ ] Secret Reference blocker 输出建议传入 `--github-key <path>` 或交互选择 key。
- [ ] Stale Plan blocker 输出建议重新运行 `plan` 或 `apply`，并说明外部 edit 已发生。
- [ ] Pending Work blocker 输出建议重新运行 `apply` 以恢复或完成 pending work。
- [ ] Owner action required 输出说明完成系统对话或外部动作后重跑 `apply`。
- [ ] Partial 和 unhealthy 输出建议运行 `doctor` 或针对失败 Component 重跑 `apply --component <id>`，前提是该建议与当前 blocker 一致。
- [ ] Tests 覆盖每类 blocker/outcome 的 next-action 文案和优先级。
