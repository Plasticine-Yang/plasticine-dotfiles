# 08 — 让 Candidate 原子自安装并执行首次 Apply

**What to build:** 让已验证的 Release Candidate 在一个连续的独占操作中检查本机兼容性、原子安装自身并执行首次 Apply，使 Owner 在升级、回滚或首次安装失败时始终保有一个明确且可恢复的 CLI 状态。

**Blocked by:** 03 — 协调并发 Reconciliation 并拒绝 stale Plan；04 — 恢复中断的 Component Apply；06 — 安全迁移并验证 Reconciliation State

**Status:** ready-for-agent

- [x] Release Candidate 提供不出现在公共帮助中的安装入口；开发构建仍可 Plan 和 Apply，但该入口会明确拒绝开发构建自安装。
- [x] Candidate 从只读兼容性检查开始，到可执行文件切换及首次 Apply 结束为止持续持有 Plasticine 独占锁；锁竞争会快速失败并报告持有者信息。
- [x] Candidate 在替换任何内容前同时验证 Reconciliation State schema 与遗留 pending work；损坏、未知、较新或无法安全恢复的状态会零写入阻塞，并保留当前已安装 CLI。
- [x] 空安装目标和可识别的兼容 Plasticine CLI 都能被原子安装或替换；目标若是无法证明兼容的可执行文件则拒绝覆盖。
- [x] 安装中断或切换失败不会留下半写入的稳定入口；已有 CLI 保持可执行，首次安装则不会把不完整文件呈现为已安装 CLI。
- [x] 原子切换成功后，Candidate 在同一受保护操作内执行首次 Apply，并将收到的 Apply argument vector 原样交给 CLI command parsing；Candidate 不解释或复制当前及未来 Apply options 的业务语义。
- [x] 一旦原子切换成功，新 CLI 即成为保留版本；首次 Apply 被拒绝、部分成功或失败时返回对应结果，但不会回退可执行文件，Owner 可直接用新 CLI 诊断并重试。
- [x] 隔离 Workstation 测试覆盖首次安装、兼容替换、未知目标、schema 不兼容、pending work、安装中断，以及首次 Apply 成功、拒绝、部分成功和失败；成功路径再次运行不会产生破坏性副作用。
