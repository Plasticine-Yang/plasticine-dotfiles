# 03 — 在 shell Component 中安装 Antidote

**What to build:** `shell` Component 通过 Managed Tool 管线安装 Release 固定的 Antidote payload，并提供稳定 source shim 供受管 Zsh 配置加载。

**Blocked by:** 01 — 支持 Managed Tool 目录 payload；02 — 将 Antidote 加入 Tool Lock

**Status:** ready-for-agent

- [ ] Antidote 不新增公开 Component ID；它作为 `shell` Component 的实现细节参与 Plan、Apply、Doctor 和 failure reporting。
- [ ] Plan 离线识别缺失、版本不符或 drifted Antidote payload，并报告为 `shell` 的 Managed Tool 变化；Plan 不下载、不写文件、不 clone 插件。
- [ ] Apply 经授权后复用 Managed Tool cache、checksum、directory payload 和 journal/precondition 语义安装 Antidote。
- [ ] 受管稳定 source shim 位于 Plasticine Home 内，指向当前 versioned Antidote payload；Zsh 配置不直接散落多个 versioned path。
- [ ] Antidote 安装失败只阻塞 `shell` 及依赖 `shell` 的下游 Component；独立 Component 仍按组件图继续。
- [ ] 首次 Apply 成功后再次 Apply 不重新下载、不重写、不重新切换 Antidote payload 或 source shim。
- [ ] Tool Lock 切换 Antidote 版本时，成功切换后清理旧 Antidote payload；失败时保留旧可用 payload。
- [ ] Contract tests 覆盖 Plan changes、Apply materialization、second Apply no-op、checksum failure isolation、version switch cleanup、Doctor healthy/unhealthy。
