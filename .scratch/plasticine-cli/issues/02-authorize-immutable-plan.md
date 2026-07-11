# 02 — 授权并执行同一个不可变 Plan

**What to build:** 让 Owner 在 Apply 修改 Workstation 前只看到并授权一次完整 Plan，随后执行的必须正是该 Plan；交互式、无人值守和 System Change 场景都具有清楚且可脚本判断的授权与输出行为。

**Blocked by:** 01 — 首次收敛个人 Git 配置

**Status:** implemented

- [x] Apply 完成全部只读发现后一次性展示 changes、blockers、Conflicts、Scope changes、state migrations、System Changes、component skips 和 Retirements 中当前存在的项目；任何 planning failure 都在授权前以零 mutation 结束。
- [x] Apply 授权后执行展示过的同一个 immutable Plan；测试中即使后续观察可能产生不同工作，也不得执行未展示的 mutation 或重新扩充 Plan。
- [x] 交互式 Apply 从 controlling terminal 读取确认，即使标准输入来自管道也不会消费 Bootstrap 数据；拒绝授权返回 operational failure 且不修改 Workstation。
- [x] 没有可用 TTY 时，Apply 必须由显式 `--yes` 才能继续；CI 或输入重定向本身绝不构成隐式授权。
- [x] 任何包含 System Change 的 Plan 除普通确认外还要求 `--allow-system`；缺少该授权时 user-scoped 与 system-scoped mutation 均不开始，并且 Plasticine 本身始终以普通用户运行。
- [x] `plan` 成功计算时返回 0，即使有变化；完整 Apply 与健康 Doctor 返回 0；blocked、denied、partial、failed、unhealthy 返回 1；usage error 返回 2；中断返回 130。
- [x] 人类可读输出在 TTY 中可使用颜色，在非 TTY 或设置 `NO_COLOR` 时不含颜色控制码，且不承诺 JSON 或内部 Action schema。
- [x] CLI contract tests 覆盖 controlling terminal、管道输入、`--yes`、`--allow-system`、TTY/非 TTY、`NO_COLOR`、全部稳定退出状态和 Ctrl-C；业务策略仍只在 Reconciler seam 测试一次。
