# 23 — 删除 legacy 流程并完成仓库 cutover

**What to build:** 让 Go Workstation CLI、最小 Bootstrap 与嵌入式手写 Desired State 成为仓库唯一的安装和配置路径，同时保留手工 Reference Configuration 并记录新的 Owner workflow。

**Blocked by:** 18 — 集成 macOS Keychain；20 — 完成有界且只读的 Doctor 网络诊断；22 — 执行有边界的旧 Release rollback

**Status:** ready-for-agent

- [ ] canonical install entry 是校验 checksum 的最小 Bootstrap，而不是历史上依赖 checkout 的 installer。
- [ ] 删除 legacy installers、uninstallers、过时 component flags、checkout assumptions 和不安全的历史清理行为，而不是用 compatibility code 包装它们。
- [ ] 手写 Git、Zsh 与 Neovim 配置分别只有一个嵌入式 Desired State source。
- [ ] 生成式 plugin loaders、caches、plugin trees 和其他 Tool-managed State 不进入 Release inputs。
- [ ] 个人 Git Desired State 不包含明文 credential-store helper。
- [ ] 删除过时的 Git、Zsh、Neovim、Lazygit 配置说明和重复配置源。
- [ ] VS Code 资料继续作为 Reference Configuration 供手工复制，并排除在 Release、Plan、ownership 和 drift 行为之外。
- [ ] Anthropic 或 Claude、Clash、WSL2、proxy-utils 与 environment-secret 配置材料不再具有活跃的仓库集成或安装路径。
- [ ] cutover 不引入 Nerd Font 管理、额外签名系统、Git history rewrite、Backup restore/prune 命令或历史 checkout 的 compatibility migration。
- [ ] 文档覆盖固定 curl 安装流程、精确版本选择、Plan、Apply、Doctor、Version、非交互授权、System Change 授权、adoption 与 Component narrowing。
- [ ] 文档覆盖公司 Workstations 的持久 exclusion Scope，并说明排除个人 Git 配置后 Plasticine 不会读取它。
- [ ] 文档覆盖显式 GitHub 私钥选择、手工登记公钥、macOS Keychain 行为和共享 Linux agent。
- [ ] 文档说明四个 Artifact Targets、Support Floors，以及其他兼容 Linux 环境的 best-effort boundary。
- [ ] 文档说明只有在新的 Apply 成功后，才手工清理旧仓库 checkout。
- [ ] 仓库开发文档与 agent 文档不打包进 Release artifacts。
- [ ] 删除 legacy sources 后完整 test suite 仍保持绿色，证明运行时和测试都不再依赖它们。
