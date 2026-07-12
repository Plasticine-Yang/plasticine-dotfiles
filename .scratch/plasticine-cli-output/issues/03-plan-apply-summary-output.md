# 03 — 优化 Plan 和 Apply 摘要输出

**What to build:** `plan` 和 `apply` 输出先展示人类可扫描的 Component 总览，再按风险和 Component 分组展示详细 changes。

**Blocked by:** 01 — 建立 CLI Result renderer seam；02 — 增加 TTY 颜色策略

**Status:** ready-for-agent

- [ ] 第一屏展示 command、outcome、target、support、Desired State、active/excluded/suspended Component 数量。
- [ ] Component summary 按状态分组展示：will change、blocked、skipped、suspended、no change/succeeded。
- [ ] System Changes、Conflicts、Retirements 和 Blockers 在 routine file writes 前展示。
- [ ] Changes 按 Component 分组，再按 kind/resource kind 展示，路径和 summary 保持可复制。
- [ ] Apply 输出区分 planned effects、actual durable effects、partial failure 和 no-change。
- [ ] 对 `--component` one-shot filtering 的输出要能看出本次只覆盖哪些 Components，且不误导为 Scope 变更。
- [ ] Tests 覆盖 changes planned、applied、no-change、blocked、partial、scope replacement、system change、retirement、conflict。
