# 06 — 文档和 gates 覆盖 CLI 输出体验

**What to build:** 文档说明新的 CLI 输出结构、颜色策略和失败指引，并确保 release gates 覆盖人类可读输出的关键路径。

**Blocked by:** 05 — 优化 Doctor 可读输出

**Status:** ready-for-agent

- [ ] README 或 CLI 文档展示 `plan`、`apply`、`doctor` 的简短示例输出。
- [ ] 文档说明颜色策略、`NO_COLOR` 和显式 color override。
- [ ] 文档说明失败输出中的 next-action 只是建议，仍需 Owner 审查风险。
- [ ] 测试覆盖 TTY/non-TTY/NO_COLOR 输出，避免 ANSI escape 污染日志。
- [ ] `go test ./...`、`go vet ./...`、`git diff --check`、`scripts/validate-release.sh` 全部通过。
- [ ] 双轴 code review 覆盖 Standards 和 Spec：Standards 关注输出稳定性、脱敏和测试粒度；Spec 关注可读性、颜色和失败指引是否完整。
- [ ] 若输出格式改变影响 smoke tests，更新 smoke tests 只断言稳定关键行，不绑定无关排版。
