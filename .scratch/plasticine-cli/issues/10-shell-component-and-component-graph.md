# 10 — 收敛 Shell Component 与 Component 图

**What to build:** 让 Owner 能用 shell Component 收敛集中式 Zsh 环境、Plasticine PATH 和登录 shell，同时让所有 Component 依赖、System Dependency 派生以及失败传播遵循一张可验证的图。

**Blocked by:** 07 — 显式接管 Conflict 并保留 Backup

**Status:** ready-for-agent

- [x] Desired State 使用稳定 Component ID shell、git-config、github-ssh、neovim、lazygit、fnm 和 uv，并表达 github-ssh 与 fnm 对 shell 的依赖。
- [x] 每个启用 Component 按已接受的图派生 Zsh、Git、OpenSSH 和 CA System Dependencies；这些依赖不能通过 Component blacklist 排除，且个人 git-config 被排除时仍可为其他 Component 派生 Git 能力。
- [x] Plan 在任何写入前验证所选图；shell 被排除而 github-ssh 或 fnm 仍启用时成为 blocker，--component 也不能绕过缺失依赖或扩张持久 Scope。
- [x] shell 的离线 Plan 显示集中式手写 Zsh 配置、唯一必要的传统 Zsh 启动 shim、Plasticine 稳定 launch entries 的 PATH 集成、Zsh capability 和必要的登录 shell System Change。
- [x] 授权 Apply 原子物化 shell 配置与 shim，并将 Antidote 的受支持 runtime root 集中到 Plasticine Home；插件、生成 loader、插件 cache 和 shell history 保持 Tool-managed State，不进入 drift、Backup 或 ownership。
- [x] 需要更改登录 shell 时，Apply 将 chsh 作为单独授权的 System Change 执行，只提升必要子进程；它不 source 配置、不替换当前进程，并提示 Owner 在新终端中生效。
- [x] 某个 Component 失败时只跳过图中的下游 Component，独立分支继续 Reconciliation，最终结果明确区分成功、skipped 和 partial failure；重新 Apply 会从实际状态继续。
- [x] 已满足的 Zsh、PATH、配置和登录 shell 再次 Plan/Apply 时无变更且不重复 chsh；隔离 Workstation 测试验证图校验、依赖顺序、下游跳过、独立分支继续、集中式 shell 配置和不触碰 Tool-managed State。
