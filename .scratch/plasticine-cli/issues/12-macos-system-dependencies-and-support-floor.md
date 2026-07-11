# 12 — 配置 macOS System Dependencies 与 Support Floor

**What to build:** 让 macOS Workstation 只通过 Apple 支持的机制补齐所需系统能力，并让所有平台在进入 Reconciliation 前得到一致的 Support Floor 与 best-effort 判定，而不是猜测未知系统命令。

**Blocked by:** 10 — 收敛 Shell Component 与 Component 图

**Status:** implemented

- [x] 平台策略把 macOS 13+、Debian 12+ 和 Ubuntu 22.04+ 的 amd64/arm64 定义为完整 Reconciliation Support Floor，并在 Plan 与 Doctor 中明确报告当前 Workstation 的支持级别。
- [x] 兼容的旧系统和其他 64 位 Linux 可继续执行可证明安全的 binary 与 user-scoped 行为，但需要未知 package manager、service manager 或其他系统机制的 System Change 会明确 unsupported，而不是被猜测执行。
- [x] 不受支持的操作系统、架构或 32 位环境在 mutation 前得到稳定、可理解的 blocker；支持级别不会被普通授权参数覆盖。
- [x] macOS Plan 离线观察启用 Components 所需的 Git、Zsh、OpenSSH、CA 与 Apple development tool capabilities；已满足的能力不会产生 installer、Homebrew、升级或降级动作。
- [x] 缺少 Apple Command Line Tools 时，Plan 显示一个独立 System Change 和 Owner action；只有普通授权与 --allow-system 同时具备时，Apply 才启动 Apple 官方安装器。
- [x] 启动官方安装器后，依赖该能力的 Components 报告 awaiting Owner action，独立 Components 继续，Apply 返回非成功结果并指示完成系统对话框后重新运行；Apply 不把“已启动”误记为“已安装”。
- [x] Plasticine 不安装或管理 Homebrew，不调用非官方静默 Apple installer，也不尝试在 GUI 安装未完成时绕过 capability 检查；后续 Apply 只依据重新观察到的系统状态继续。
- [x] deterministic platform/process 测试覆盖所有 Support Floors、四个受支持 OS/architecture 组合族、旧版本 best effort、其他 Linux 的 unsupported System Change、Apple 工具已存在/缺失/安装器失败/重跑；普通测试不启动真实系统安装器或 chsh。
