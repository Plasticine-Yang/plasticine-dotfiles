# 11 — 配置 Debian/Ubuntu System Dependencies

**What to build:** 让受支持 Debian 和 Ubuntu Workstation 能按启用 Component 的实际能力缺口一次性安装所需 System Dependencies，同时将提权、失败和中断限制在可观察、可重复执行的系统变更边界内。

**Blocked by:** 10 — 收敛 Shell Component 与 Component 图

**Status:** implemented

- [x] Plan 离线检查 Git、Zsh、OpenSSH 和 CA 等能力，只为启用 Component 缺失或低于最低能力的依赖显示 System Changes；已满足的能力不会被精确 pin、升级或降级。
- [x] 同一次 Apply 把所有缺失能力聚合为一次 package index update 和一次不安装推荐包的最小 package install，而不是按 Component 重复调用包管理器。
- [x] System Changes 只有在普通 Apply 授权和 --allow-system 同时具备时才执行；Plasticine 始终以 Owner 身份运行，仅具体 apt 子进程通过系统 sudo 机制提权。
- [x] Apply 不执行全局 upgrade、不降级已满足的包、不卸载 System Dependencies，也不读取、传递、缓存或记录 sudo 密码。
- [x] sudo 可直接授权或可使用控制终端时遵循系统原生认证；需要密码但没有可用终端时快速、明确失败，不挂起也不推测凭据。
- [x] package-manager effect 在执行后按实际能力重新观察；中断或不确定结果由下次 Apply 重观察而非盲目回滚，已完成安装不会被无条件重复。
- [x] apt 失败只使依赖这些能力的 Components 失败或 skipped，独立且能力已满足的 Components 仍可继续，最终 Apply 返回 partial/failed 结果。
- [x] scripted process 测试覆盖 Debian 与 Ubuntu、多个 Component 的 package 聚合、全部能力已满足、禁止 upgrade/downgrade、授权组合、无 TTY sudo、apt 中断和重跑；普通测试绝不执行真实 sudo 或 apt。
