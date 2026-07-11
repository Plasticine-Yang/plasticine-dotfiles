# 05 — 持久化 Workstation Scope 与 Suspension

**What to build:** 让 Owner 能用 exclusion-only 的 Workstation Scope 非交互地声明公司机器不接受个人 Components，并在后续运行中复用该选择；已受管但后来排除的 Component 只被 Suspended，既不被检查也不被删除。

**Blocked by:** 03 — 协调并发 Reconciliation 并拒绝 stale Plan

**Status:** ready-for-agent

- [ ] `--exclude` 接受稳定 Component ID 并表示完整 intended exclusion set；它替换而非追加既有黑名单，且不存在 allowlist、profile 或交互式 Component selector。
- [ ] Plan 预览 Scope replacement、active Components 与 Suspended Components，但不持久化选择，也不因排除项读取或修改对应内容。
- [ ] 所有 blocker 与授权通过后，Apply 在任何 Component effect 之前原子持久化新 Workstation Scope；随后发生 partial failure 时该黑名单仍保留供下一次运行复用。
- [ ] 不传 `--exclude` 的 Plan 与 Apply 复用 persisted Scope；Release 未来新增且未显式排除的 Components 默认 active。
- [ ] `--component` 只能将本次 Plan 或 Apply 缩窄到当前 Scope 内的 active Components，不持久化、不启用 excluded Component，也不把本次省略解释成 Suspension 或 Retirement。
- [ ] 已有 ownership 的 Component 被排除后成为 Suspended Component；Reconciliation 不读取、做 drift check、备份、修改或删除其内容，也不丢失 ownership 和既有 Backup metadata。
- [ ] 重新从 Scope 中移除 exclusion 后，Component 从保留的 ownership 继续正常 Reconciliation，而不是被当作首次安装或通过内容相等猜测 ownership。
- [ ] 当 `git-config` 被排除时，即使公司 Git 配置存在且内容任意，Plasticine 也完全不读取、不备份、不修改该配置；其他 active Components 未来仍可独立派生 Git System Dependency。
- [ ] Scope tests 覆盖 exclusion-set replacement、plain-run reuse、future Component default activation、partial-failure persistence、one-run narrowing、Suspension 零观察与公司 Git 路径零观察。
