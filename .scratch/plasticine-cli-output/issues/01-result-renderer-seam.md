# 01 — 建立 CLI Result renderer seam

**What to build:** 将 `cmd/plasticine` 中直接打印 Result 的逻辑收拢到一个小的 presentation 模块，为后续分组、颜色和 next-action 输出提供可测试 seam。

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] 保持 Reconciler Result 作为 policy seam；renderer 只消费 Result，不重新规划、不读取 Workstation、不执行 mutation。
- [ ] 当前 `plan`、`apply`、`doctor`、`version` 命令语义和 exit status 不变。
- [ ] renderer 接受 command、Result、output capabilities，并返回或写出 deterministic text。
- [ ] 输出顺序稳定：summary、components、risks、changes/details、durable effects、checks。
- [ ] 原有重要信息不丢失：outcome、target、support、desired state、active/excluded/suspended Components、changes、conflicts、retirements、blockers、durable effects、checks。
- [ ] 单元测试覆盖 renderer 的纯文本输出，不需要真实 Reconciliation。
- [ ] CLI integration tests 证明命令仍使用新的 renderer，并保持 non-TTY 输出可断言。
