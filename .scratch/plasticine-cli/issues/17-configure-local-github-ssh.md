# 17 — 配置本机 GitHub SSH 与 Secret Reference

**What to build:** Owner 可以显式选择一份本机 GitHub 私钥，让 Plasticine 安全建立可重复验证的本地 OpenSSH 配置、Release 固定的 GitHub host trust 与非敏感 Secret Reference，而不会复制 Secret、猜测密钥或获得任何 GitHub 远端写权限。

**Blocked by:** 10 — 收敛 Shell Component 与 Component 图；11 — 配置 Debian/Ubuntu System Dependencies；12 — 配置 macOS System Dependencies 与 Support Floor

**Status:** implemented

- [x] github-ssh 首次启用或现有 Secret Reference 无效时，只接受控制终端中的显式选择或 `--github-key`；非交互运行缺少选择时明确阻塞，并且从不扫描或猜测常见私钥位置。
- [x] 所选私钥必须是当前 Owner 拥有的普通文件、具有限制性权限、可由 OpenSSH 工具读取并可导出稳定公钥 fingerprint；任一检查失败都在 mutation 前阻塞，Plasticine 不修改外部 Secret 的权限或内容。
- [x] Reconciliation 只持久化规范化位置与公钥 fingerprint 作为 Secret Reference；私钥内容和 passphrase 不进入 Desired State、Plan、Reconciliation State、pending journal、Backup、输出或日志。
- [x] 有效 Secret Reference 在后续非交互 Plan 与 Apply 中自动复用；文件消失、权限变得不安全或 fingerprint 改变时要求 Owner 显式重新选择，而不是自动接受替换。
- [x] Plan 保持离线，并完整描述本地 GitHub SSH 配置、专用 known-hosts 输入、SSH Managed Block、Secret Reference 变化以及所有 Conflict，且不运行网络探测或 `ssh-keyscan`。
- [x] 经授权的 Apply 物化完整的中央 GitHub SSH fragment 与 Release 内嵌的 GitHub 官方 host keys，采用专用受管 known-hosts 输入并禁止 trust-on-first-use；旧 Release 遇到未知的新 host key 时保持 fail closed。
- [x] SSH Managed Block 是对 Owner 控制配置的唯一初始局部所有权：新建或空文件可直接收敛，首次插入已有内容必须 adoption 并保存完整 Backup，标记缺失、重复或畸形时阻塞，标记外每个字节保持不变。
- [x] 只有 git-config 与 github-ssh 同时 active 时才生成 GitHub HTTPS-to-SSH rewrite；任一 Component 被排除时都不产生该组合配置。
- [x] Apply 只配置当前 Workstation，不注册 GitHub 公钥、不写远端账户、不复制或备份私钥；首次收敛后再次 Apply 无 mutation。
- [x] 本地 Doctor 只读验证 Secret Reference、私钥 owner/type/mode/fingerprint、受管 SSH 配置、Managed Block 和 Release host keys；缺失、漂移或不安全状态报告 unhealthy，且不会提示输入、加载私钥、联网或修改任何内容。
