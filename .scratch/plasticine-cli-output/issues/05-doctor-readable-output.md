# 05 — 优化 Doctor 可读输出

**What to build:** `doctor` 输出按健康状态和诊断类型分组，让 Owner 能快速区分本地 drift、state 问题、网络诊断和 GitHub SSH 诊断。

**Blocked by:** 01 — 建立 CLI Result renderer seam；02 — 增加 TTY 颜色策略；04 — 为失败输出提供 next-action 指引

**Status:** ready-for-agent

- [ ] Doctor summary 展示 overall outcome、healthy/unhealthy check 数量和最重要失败项。
- [ ] Unhealthy checks 优先展示，并保留 check name、分类和脱敏 message。
- [ ] Healthy checks 可折叠为简短列表或 grouped section，但 non-TTY 输出仍包含可审计明细。
- [ ] HTTPS diagnostic、GitHub SSH diagnostic、managed resource checks、support-floor checks 分组清楚。
- [ ] Doctor 输出不泄露 proxy credential、Secret path 内容以外的私密材料，保持现有脱敏语义。
- [ ] Unhealthy 输出包含 next action，例如检查网络、重跑 apply、重新提供 key、修复 drift 后 rerun。
- [ ] Tests 覆盖 all healthy、mixed healthy/unhealthy、network classified failure、github-ssh inactive skip、suspended orphan。
