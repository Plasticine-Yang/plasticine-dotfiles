# 04 — 恢复中断的 Component Apply

**What to build:** 让 Owner 在 Apply 于任一 Component effect 前后中断时，可以在下一次运行中看到未完成工作，并由 Apply 安全地确认已完成效果或幂等续跑；不能证明的状态必须阻塞而不是盲目回滚。

**Blocked by:** 03 — 协调并发 Reconciliation 并拒绝 stale Plan

**Status:** ready-for-agent

- [ ] 每个 Component 在第一次 mutation 之前原子写入 pending journal；journal 只记录恢复所需的非敏感 intent、precondition 和进度，不含 Secret、Secret 内容或可能携带凭据的环境值。
- [ ] 每个 effect 完成后先观察并验证 durable outcome，只有全部 Component effects 被证明成功后才原子提交 ownership 并清除对应 journal。
- [ ] Plan 遇到 pending work 时只读报告中断位置、可证明状态和 blocker，不执行 finalize、resume、cleanup 或 state migration。
- [ ] 后续 Apply 对已能证明完成的 effect 直接 finalize，对明确定义为幂等且仍满足 precondition 的 effect安全续跑，不重复已确认的副作用。
- [ ] 无法区分“未执行、部分执行或被外部修改”的 ambiguous effect 成为 blocker，保留 journal 和现场供 Owner 处理，绝不凭猜测提交 ownership。
- [ ] 外部 package-manager 类 effect 使用重新观察 capability 的恢复策略，而不是尝试逆向执行或声称 rollback；该策略可由后续 System Dependency Component 复用。
- [ ] 在关键 effect 之前、期间和之后注入 failure 或 interruption 后，下一次 Apply 的结果都确定、可重复，且成功恢复后再运行一次没有变化。
- [ ] pending journal 的损坏或不受支持版本以零 mutation 阻塞；日志、Plan、state 和测试 failure output 均证明不会出现 Secret。
