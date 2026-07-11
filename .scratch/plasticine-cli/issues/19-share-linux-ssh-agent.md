# 19 — 在 Linux 终端间共享 SSH Agent

**What to build:** Owner 在受支持的 Debian/Ubuntu Workstation 上使用 github-ssh 时，可以让所有终端共享一个固定 socket 的 user-level systemd ssh-agent，并仅在目标 fingerprint 缺失时加载所选私钥，从而不再为每个会话手工执行 agent 初始化。

**Blocked by:** 11 — 配置 Debian/Ubuntu System Dependencies；17 — 配置本机 GitHub SSH 与 Secret Reference

**Status:** implemented

- [x] 在受支持 Linux 且 github-ssh active 时，Plan 离线识别 user-level systemd agent、固定共享 socket、Shell 导出和条件式私钥加载的缺失或漂移，完整展示效果且不启动服务或加载密钥。
- [x] 经授权的 Apply 建立并启动单个 Owner 级 systemd ssh-agent，使其使用 Plasticine Home 下的固定 runtime socket；整个行为不以 root 运行，也不创建每终端独立 agent。
- [x] 受管 Shell 统一导出共享 socket，并只在该 agent 中缺少 Secret Reference 指定的公钥 fingerprint 时调用私钥加载；已存在目标 fingerprint 时新终端不重复加载或提示。
- [x] 两个独立的新终端观察到同一个 agent 与 socket，均无需手工执行 `eval`；agent 重启后，加密私钥至多在首次必要加载时由 OpenSSH 提示一次，Plasticine 不存储 passphrase。
- [x] 私钥加载失败不会复制、修改、备份或泄露 Secret，并产生可重试的 github-ssh Component 失败；后续 Apply 重新观察 agent 与 fingerprint，而不是盲目假定前次效果成功。
- [x] user-level service、Shell 集成和共享 socket 遵循重复执行语义；首次 Apply 收敛后再次 Apply 不重复创建 agent、不重写健康配置，也不再次加载已存在的 fingerprint。
- [x] 不满足受支持 Debian/Ubuntu 与 systemd user-session 条件的 Linux 明确报告该 agent 行为不受支持，不猜测其他 init system、桌面 keyring 或每 shell 的临时替代方案。
- [x] 本地 Doctor 无提示、无 mutation 地验证 user service、共享 socket 的 owner/type、Shell 导出和目标 fingerprint；服务停止、socket 异常或密钥未加载时报告 unhealthy 并给出可重试诊断，但不自行启动 agent 或运行私钥加载。
