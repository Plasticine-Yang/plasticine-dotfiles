# 09 — 通过最小 POSIX Bootstrap 安装 Candidate

**What to build:** 让 Owner 能从固定 HTTPS 地址通过 POSIX shell 获取与 Workstation 匹配的不可变 Release Candidate，校验其完整性，并把所有初始化意图原样交给 Candidate，而不在网络脚本中实现任何配置策略或提权逻辑。

**Blocked by:** 08 — 让 Candidate 原子自安装并执行首次 Apply

**Status:** ready-for-agent

- [x] Bootstrap 只负责 Release 选择、Artifact Target 识别、原始 Candidate 与 Release checksum 获取、SHA-256 校验、可执行权限和 Candidate handoff；它不执行 Workstation 配置、状态迁移或 sudo。
- [x] 未指定版本时固定入口选择 latest stable Release；PLASTICINE_VERSION 选择精确 Release，prerelease 只能被显式选择，mutable branch 内容不会被执行。
- [x] macOS/Linux 与 amd64/arm64 的四种 Artifact Target 都映射到正确的原始二进制；不支持的操作系统、架构和 32 位环境在下载或执行 Candidate 前给出明确错误。
- [x] Candidate 只有在其摘要与所选 Release 的 checksums 清单完全匹配后才会执行；摘要不匹配、清单缺项、下载中断或不完整文件都不会被提升或执行。
- [x] Bootstrap 不依赖 Go、归档解包器或项目 checkout，也不会为 Candidate 安装之外的工作创建持久状态；下载或 handoff 前失败时保留已有 CLI。
- [x] fixture Candidate 证明传给 Bootstrap 的 opaque argument vector 按原边界和顺序到达 Candidate，至少覆盖 --exclude、--component、--github-key、--yes、--allow-system 和 --adopt；Bootstrap 不解释这些 options，也不让 shell 重新解释它们。
- [x] 通过 curl pipe 启动时，交互授权仍由 Candidate 使用控制终端完成；无终端且未授权时可以保留已安装 Candidate，但首次 Apply 按既定规则拒绝。
- [x] POSIX shell 语法、ShellCheck 和本地 HTTP fixture 测试覆盖 stable/精确版本选择、四目标映射、不支持目标、checksum 失败、中断下载及精确参数转发，测试不依赖真实 GitHub Release。
