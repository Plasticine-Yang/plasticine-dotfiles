# 04 — 物化 Zsh 插件声明与 Antidote bootstrap

**What to build:** `shell` Component 物化受管 `.zsh_plugins.txt` 和 Zsh bootstrap，使新终端通过 Antidote 生成并加载静态插件 bundle，同时保持 Apply 的网络边界。

**Blocked by:** 03 — 在 shell Component 中安装 Antidote

**Status:** ready-for-agent

- [ ] 受管插件声明文件位于 `~/.plasticine/config/zsh/.zsh_plugins.txt`，内容来自 embedded Desired State，而不是仓库 checkout、用户 YAML、profile 或 machine-local override。
- [ ] 插件声明中的初始插件集合只包含明确需要的 Zsh UX 插件，并可通过 Release review 变更；不在运行时解析推荐列表或 latest 配置。
- [ ] 受管 `.zshrc` 设置 `PLASTICINE_HOME`、`PATH`、`ANTIDOTE_HOME`、Antidote snapshot/cache zstyles，并继续保留 fnm 和 GitHub SSH 既有条件集成。
- [ ] 受管 `.zshrc` source 稳定 Antidote source shim，而不是直接 source 仓库 checkout 或 Homebrew path。
- [ ] 受管 `.zshrc` 仅当静态 bundle 早于插件声明时运行 `antidote bundle`，然后 source generated static bundle；steady-state shell startup 不运行 plugin update。
- [ ] `antidote bundle` 和插件 clone 只发生在用户启动 Zsh 的 Tool-managed runtime 中，不作为 Apply mutation、Plan evidence 或 Doctor repair。
- [ ] 一次性 `--component shell` 过滤不会移除仍处于持久 Scope 中的 fnm/GitHub SSH 相关 shell integration。
- [ ] Contract tests 覆盖 `.zsh_plugins.txt` materialization、bootstrap 内容、fnm integration preserved、excluded fnm omission、second Apply no-op，以及没有 Apply-time plugin clone。
