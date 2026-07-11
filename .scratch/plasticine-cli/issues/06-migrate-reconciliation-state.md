# 06 — 安全迁移并验证 Reconciliation State

**What to build:** 让 Owner 升级或回退 CLI 时，Plasticine 能在 mutation 前判断本地 Reconciliation State 是否可理解，把受支持迁移完整展示在 Plan 中，并只在授权 Apply 后原子持久化；损坏或不兼容的 state 必须保留现场并阻塞。

**Blocked by:** 03 — 协调并发 Reconciliation 并拒绝 stale Plan

**Status:** ready-for-agent

- [ ] Reconciliation State 带有明确 schema version；当前 schema 可稳定 round-trip ownership、applied Release 或 Desired State digest、Scope、Backup metadata、pending work 和 Secret References，而不会把 Workstation observation 当成 Desired State。
- [ ] 读取受支持的旧 schema 时只在内存中产生 migration result，Plan 明确展示版本变化及其 durable effect，且 planning、拒绝授权或 planning failure 后原始 state 字节不变。
- [ ] 授权 Apply 将已经展示的 migration 原子持久化；中断只会留下完整旧 state 或完整新 state，不会留下半写文件或伪造已完成 Component ownership。
- [ ] malformed、corrupt、unknown 和高于当前 CLI 支持范围的 schema 均在任何 mutation 前阻塞并保留原始 state；旧 CLI 永不降级较新的 schema。
- [ ] 提供与普通 state loader 共享规则的 read-only compatibility result，供后续 candidate handoff 在替换 CLI 前区分 compatible、migration-required 与 incompatible，且该检查自身不获取 mutation authority。
- [ ] Reconciliation State 丢失时，Plasticine 不因现有内容与 Desired State 字节相等而推断 ownership；候选 Managed Paths 保持 unmanaged，并交由后续 Conflict policy 明确处理。
- [ ] State diagnostics 能区分可迁移、损坏、不支持和较新版本，但不输出 opaque Backup 内容、Secret 或可能敏感的 state payload。
- [ ] State tests 覆盖首次 state、每个支持迁移、atomic replacement interruption、corruption、unknown/newer schema、read-only candidate compatibility、state loss 和 downgrade refusal。
