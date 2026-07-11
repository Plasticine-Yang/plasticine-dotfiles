# 03 — 协调并发 Reconciliation 并拒绝 stale Plan

**What to build:** 让多个 Plasticine 进程安全共享同一 Workstation：只读操作可以并行，Apply 与未来的 candidate replacement 获得独占权，同时任何 Plan 之后发生的外部修改都被识别为 stale Plan 而不是遭到覆盖。

**Blocked by:** 02 — 授权并执行同一个不可变 Plan

**Status:** implemented

- [x] Plan 与 Doctor 在完整只读操作期间持有 shared lock，并能彼此并发执行；Apply 从内部 Planning 开始直到结果与 state 落定始终持有 exclusive lock。
- [x] 独占锁能力可被 candidate replacement 复用，使未来的 CLI replacement 与所有 Plan、Apply、Doctor 互斥，而不引入第二套锁语义。
- [x] 发生 lock contention 时快速失败，不排队无限等待，并以不泄露敏感参数的方式报告 holder PID 与 command 信息。
- [x] 锁由进程生命周期可靠释放；正常退出、中断和崩溃后不会留下永久阻塞后续 Reconciliation 的陈旧所有权。
- [x] immutable Plan 为每个 mutation 携带观察时的 precondition digest，并在实际 mutation 前重新检查对应 Workstation 状态。
- [x] 外部进程在授权前后改动目标时，受影响操作返回清楚的 stale Plan failure，不覆盖新内容，也不把该操作记为成功 ownership。
- [x] 一个 stale precondition 只按既定 Apply 结果模型影响相关 Component；不得触发未计划工作、猜测合并或声称全局 rollback。
- [x] deterministic concurrency tests 覆盖 shared/shared、shared/exclusive、exclusive/exclusive、holder diagnostics 和外部编辑；针对真实进程的隔离测试证明跨进程锁与退出释放行为。
