# 21 — 显式 Retirement 已移除的受管资源

**What to build:** 让选定 Release 能以可见且安全的方式 Retirement 已不再属于其 active Desired State 的自有资源，同时不把单次过滤、Suspension、系统软件或 Tool-managed State 误作删除授权。

**Blocked by:** 14 — 安装 Neovim 并集中配置与 runtime；15 — 安装 uv/uvx 并集中 Python runtime；16 — 安装 fnm 并集中 Node runtime；19 — 在 Linux 终端间共享 SSH Agent

**Status:** ready-for-agent

- [ ] 当自有资源从选定 Release catalog 中移除而其 Component 仍 active 时，Plan 将其报告为独立的 Retirement。
- [ ] 通过单次 component filter 省略 Component 时，不为该 Component 产生 Retirement、ownership 变化、检查或 mutation。
- [ ] 被持久排除的 Suspended Component 即使 catalog definition 消失，也保持不被检查且内容不变。
- [ ] 本地 Doctor 报告 catalog definition 已消失的 Suspended Component，但不对其执行 mutation。
- [ ] 只有当前内容匹配最后 accepted digest 后，Apply 才删除未发生漂移的待 Retirement 受管配置、集成 shims、launchers 和 Managed Tool payloads。
- [ ] 删除成功后原子释放对应的 ownership metadata。
- [ ] 待 Retirement Managed Path 上的 Owner drift 成为 Conflict；没有显式 adoption 时保持不动。
- [ ] 已 adoption 的 Retirement drift 在删除前 byte-for-byte 创建 Backup，随后释放 ownership。
- [ ] Retirement mutation 使用正常的 precondition 与 pending journal 保证，使中断可以被安全观察并续跑。
- [ ] Retirement 永不卸载 System Dependency，也不删除 Tool-managed State。
- [ ] 经验证的普通版本切换后清理旧 Managed Tool payload，不报告为 Retirement。
- [ ] 被阻塞或部分失败的 Retirement 返回 operational failure，同时独立 Component work 仍可完成。
- [ ] Retirement 成功后重复 Apply 是 no-op，不会重建或反复删除该资源。
- [ ] Reconciler-level tests 覆盖 clean Retirement、drift、adoption、中断、Suspension、单次过滤、System Dependency 保留和 Tool-managed State 保留。
