# 24 — 建立完整 CI、构建与 Smoke Gates

**What to build:** 建立可重复、非破坏性的 validation pipeline，在任何发布 workflow 运行前证明 Reconciler contract、Bootstrap、Tool Lock 与四个 Artifact Targets 均已 release-ready。

**Blocked by:** 23 — 删除 legacy 流程并完成仓库 cutover

**Status:** implemented

- [x] CI 通过 Plan、Apply 与 Doctor 运行全部 Reconciler-level behavior tests。
- [x] Tests 断言 externally observable outcomes 与 durable effects，而不是 private Action ordering、helper structure 或具体 Adapter implementation details。
- [x] CI 只在隔离 HOME 中运行真实文件系统 integration tests，绝不读取或修改 runner user 的实际配置。
- [x] Bootstrap 通过 POSIX shell syntax validation 与 ShellCheck。
- [x] 本地 HTTP fixture tests 覆盖 stable 与精确版本选择、全部 Artifact Target mappings、下载中断、checksum mismatch 和 candidate argument forwarding。
- [x] Tool Lock validation 要求每个 Artifact Target 上的每个 Managed Tool 都具有不可变 URL、artifact type 与 SHA-256。
- [x] Tool Lock 或 Release checksum mismatch 在 artifact 被视为可发布之前使 gate 失败。
- [x] pinned Go toolchain 与 read-only module graph 在禁用 CGO 并移除本地构建路径后，为 macOS、Linux 构建 amd64、arm64 二进制。
- [x] Build metadata 仅由 tag、commit 与从源码推导的 commit time 生成，不引入 compressor 或 machine-specific metadata。
- [x] pipeline 生成四个 raw executable artifacts 与一个 checksum manifest，不使用 archive wrapping。
- [x] 原生 macOS 与 Linux smoke jobs 验证启动、Version，以及安全的 read-only 或 user-scoped 行为。
- [x] Support Floor 与 unsupported System Change policy 由 deterministic tests 和代表性的 native jobs 覆盖，而不假称测试每个未来 OS release。
- [x] 普通 CI 永不执行真实 sudo、apt、systemd mutation、login-shell change、Apple installer 或其他破坏性 host System Change。
- [x] 对相同源码与输入重新构建时，产出匹配的二进制或 actionable reproducibility failure。
- [x] tag/version、Desired State identity、Tool Lock completeness 与生成的 checksum consistency 一并校验。
- [x] 任一 test、build、validation、checksum 或 smoke job 失败，都阻止 Release artifacts 进入发布阶段。
