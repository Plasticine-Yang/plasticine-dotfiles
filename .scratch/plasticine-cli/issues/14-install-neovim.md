# 14 — 安装 Neovim 并集中配置与 runtime

**What to build:** Owner 可以通过同一个 Plan、Apply 和 Doctor 纵切面安装 Release 精确固定的 Neovim，获得不依赖仓库 checkout 的手写配置与稳定启动入口，并让 Neovim 自己管理的插件和运行时内容集中到 Plasticine Home 而不被 Reconciliation 接管。

**Blocked by:** 13 — 通过 Tool Lock 安装 Lazygit

**Status:** ready-for-agent

- [ ] Neovim 的 Tool Lock 数据为四个 Artifact Target 提供精确版本、不可变来源和 SHA-256；目标缺失、摘要不匹配或下载中断时，Neovim Component 明确失败且不会切换当前可用版本。
- [ ] Plan 离线识别缺失、版本不符或漂移的 Neovim payload、稳定启动入口和手写配置，完整报告所需变化且不下载、不写文件、不改 Reconciliation State。
- [ ] 经授权的 Apply 复用已验证的 Managed Tool 管道，原子安装并切换到精确 payload，物化 Release 内的手写 Neovim 配置，并创建可供 Zsh 与非 Zsh 调用者一致使用的稳定启动入口。
- [ ] 稳定启动入口通过 Neovim 支持的机制把配置、数据、状态与缓存根集中到 Plasticine Home；启动行为不依赖当前仓库 checkout 或解压后的 Release 目录。
- [ ] 插件管理器、插件树、生成的 loader、缓存和其他 Neovim runtime 保持为 Tool-managed State；Plan、Apply、Backup 与漂移检测均不读取、接管、修复或版本化其内容，Neovim 正常启动时仍可按自身机制联网。
- [ ] 已存在的非受管配置或 Owner drift 遵循统一 Conflict 与 adoption 规则；干净的精确版本切换不产生不必要的 Backup，切换成功前不删除旧 payload。
- [ ] 首次 Apply 收敛后再次 Apply 不下载、不重写、不重复切换，也不改变 Tool-managed State。
- [ ] 本地 Doctor 验证精确 Neovim payload、稳定启动入口、手写配置与 Reconciliation ownership；任一受管效果缺失或漂移时报告 unhealthy，同时不检查或修改 Tool-managed State。
