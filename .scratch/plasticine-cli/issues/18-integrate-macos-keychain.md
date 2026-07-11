# 18 — 集成 macOS Keychain

**What to build:** Owner 在受支持的 macOS Workstation 上使用 github-ssh 时，可以依赖系统原生 Keychain 与 SSH agent 行为复用加密私钥，无需 Plasticine 存储 passphrase 或引入额外凭据系统。

**Blocked by:** 12 — 配置 macOS System Dependencies 与 Support Floor；17 — 配置本机 GitHub SSH 与 Secret Reference

**Status:** ready-for-agent

- [x] 在受支持 macOS 且 github-ssh active 时，Plan 离线识别 Keychain 与 AddKeysToAgent 集成的缺失或漂移，并将它们作为 github-ssh 的本机受管效果展示；Plan 不读取 Keychain Secret 或触发认证。
- [x] 经授权的 Apply 通过 macOS 原生 OpenSSH/Keychain 能力配置所选私钥及 agent 集成，使加密私钥可按平台行为提示并在后续终端复用。
- [x] Plasticine 永不读取、传输、记录或自行持久化私钥 passphrase；Keychain 内部内容不进入 Desired State、Plan、Reconciliation State、pending journal、Backup、输出或日志。
- [x] Keychain 配置继续遵循统一 Conflict、adoption、Backup 和 Managed Block 规则，且不会覆盖 Owner 控制的其他 SSH 配置字节。
- [x] macOS 以外的平台不会计划或调用 Keychain 专属行为，也不会因为缺少 macOS 能力而使平台中立的 github-ssh 配置失败。
- [x] 首次 Apply 收敛后再次 Apply 不重复添加、提示或改写已健康的 Keychain/agent 集成。
- [x] 本地 Doctor 以无提示、无 mutation 的方式验证 macOS 平台能力和有效 SSH 配置中所需的 Keychain/agent 行为；配置缺失或失效时报告 unhealthy，但不读取 Keychain 内容或尝试加载私钥。
