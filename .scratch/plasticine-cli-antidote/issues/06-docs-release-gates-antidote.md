# 06 — 文档与 release gates 覆盖 Antidote

**What to build:** 文档、研究链接和 release gates 清楚覆盖 Antidote Managed Tool 的使用边界，确保发布前能证明 Tool Lock、Reconciler contract 和四平台 metadata 都包含 Antidote。

**Blocked by:** 05 — 保护 Antidote Tool-managed State 边界

**Status:** ready-for-agent

- [ ] README 或相关文档说明 Antidote 本体由 Plasticine 安装和固定，Zsh 插件 runtime 由 Antidote 自己管理。
- [ ] 文档列出受管路径与非受管 runtime 路径，避免 Owner 误以为 Plasticine 会备份或修复插件 clone。
- [ ] 文档说明修改 Zsh plugin list 需要 Release edit，而不是在 Workstation 上改 machine-local profile。
- [ ] `docs/research/zsh-plugin-managers-and-shell-comparison.md` 被 spec 或 README 引用为设计依据。
- [ ] `scripts/validate-release.sh` 继续覆盖 Go tests、Tool Lock validation、four-target builds、metadata smoke 和 checksum consistency。
- [ ] Release metadata/smoke tests 不因为 Antidote source-only artifact 或 repeated target artifact URL 产生 false failure。
- [ ] `go test ./...`、`go vet ./...`、`git diff --check`、`scripts/validate-release.sh` 全部通过。
- [ ] 完成后使用双轴 code review：Standards 关注 Managed Tool/Tool-managed State 边界，Spec 关注本 effort 的所有 tickets。
