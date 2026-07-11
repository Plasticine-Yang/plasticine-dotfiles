# 13 — 通过 Tool Lock 安装 Lazygit

**What to build:** 让 Owner 的 Lazygit Component 成为首个完整 Managed Tool 纵切面：从 Release 内精确 Tool Lock 选择可信 artifact，经可恢复下载与原子版本切换，最终通过稳定的 lazygit 和 lg 入口使用，而无需 sudo 或运行时 latest 解析。

**Blocked by:** 11 — 配置 Debian/Ubuntu System Dependencies；12 — 配置 macOS System Dependencies 与 Support Floor

**Status:** implemented

- [x] Tool Lock 为 Lazygit 固定一个精确版本，并为 macOS/Linux 的 amd64/arm64 四个 Artifact Target 完整声明不可变官方 artifact、格式和 SHA-256；缺项、重复项或无效摘要在构建验证中失败。
- [x] Plan 完全离线地从当前 Artifact Target 和 Tool Lock 计算首次安装或版本切换，不查询 latest、stable、branch 或上游 API；不支持的目标成为清晰 blocker。
- [x] 授权 Apply 仅从 Tool Lock 声明的 URL 获取 artifact，不使用 sudo；下载有界超时，遵循常规 proxy 环境变量，并在输出、错误和日志中隐藏可能含凭据的 proxy 值。
- [x] Artifact cache 以预期 SHA-256 标识内容，每次命中都重新校验；损坏命中会被安全替换，下载先写 partial 内容且仅在完整校验后原子提升。
- [x] 校验通过的 Lazygit payload 安装到 Owner 范围的精确版本位置，并在验证可执行后原子切换稳定 lazygit 与 lg symlink；调用方不依赖版本目录。
- [x] 版本切换失败、checksum 不匹配、解包失败或中断时，先前可用 payload 与 launch entries 保持工作且错误 artifact 不会成为缓存命中；旧 payload 只在新版本成功切换并验证后才可删除。
- [x] 下载或安装失败只影响 lazygit 及其下游，独立 Components 继续；成功 Apply 再次运行时不重新下载或切换，且不会把 Lazygit 自身的 runtime 数据纳入 ownership、drift 或 Backup。
- [x] 本地 HTTP fixture 与隔离 Workstation 测试覆盖四目标选择、Tool Lock 完整性、首次安装、版本升级、稳定双入口、cache 命中与损坏、checksum 失败、中断下载、proxy redaction、旧版本保留及重复 Apply。
