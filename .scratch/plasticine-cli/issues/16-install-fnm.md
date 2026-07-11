# 16 — 安装 fnm 并集中 Node runtime

**What to build:** Owner 可以通过 Plasticine 安装 Release 精确固定的 fnm，并在受管 Shell 与直接调用中使用同一稳定入口和集中式 Node runtime，同时让 Node 版本与 alias 继续由 fnm 自己管理。

**Blocked by:** 10 — 收敛 Shell Component 与 Component 图；13 — 通过 Tool Lock 安装 Lazygit

**Status:** ready-for-agent

- [ ] fnm 的 Tool Lock 数据为四个 Artifact Target 提供精确版本、不可变来源和 SHA-256；目标缺失、摘要不匹配或下载中断时，fnm Component 明确失败且不会替换当前可用版本。
- [ ] fnm 保持对 shell Component 的显式依赖；Workstation Scope 将 shell Suspended 而 fnm 仍 active 时，Plan 在任何 mutation 前阻塞，不会静默启用 shell 或留下半配置状态。
- [ ] Plan 离线识别缺失、版本不符或漂移的 fnm payload、稳定启动入口和 Shell 集成，完整报告所需变化且不下载、不写文件、不改 Reconciliation State。
- [ ] 经授权的 Apply 原子安装并切换到精确 fnm payload，创建 Zsh 与非 Zsh 调用者共用的稳定启动入口，并让后续新终端通过受管 Shell 配置获得 fnm 环境。
- [ ] 启动入口和 Shell 集成只通过 fnm 支持的机制把 fnm runtime root 集中到 Plasticine Home，不依赖仓库 checkout，也不把 Reconciliation 逻辑放入启动入口。
- [ ] fnm 安装的 Node 版本、alias、缓存及其他嵌套内容保持为 Tool-managed State；Plan、Apply、Backup 与漂移检测不读取、接管、修复或版本化这些内容。
- [ ] 成功切换前保留旧 payload；首次 Apply 收敛后再次 Apply 不下载、不重写、不重复初始化，也不改变 fnm 管理的 Node 状态。
- [ ] 本地 Doctor 验证精确 fnm payload、稳定启动入口、Shell 集成与受管 relocation 配置；受管效果缺失或漂移时报告 unhealthy，但不枚举、执行或修改 Node 版本和 alias。
