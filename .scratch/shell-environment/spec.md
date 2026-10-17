# 基础环境与交互配置拆分

非交互 Zsh 不读取 `.zshrc`，导致 Codex 等命令入口无法找到已经安装的
Node。无条件前置 fnm 默认目录又会覆盖父进程选好的 Node。

- `shell` Feature 管理轻量 `environment.zsh`，由 `.zshenv` 加载；新增区块
  追加到 Owner exports 后面，以尊重已有 `FNM_DIR`、`GOPATH` 等设置。
- `.zprofile` 在系统登录配置之后再次加载基础环境，恢复被 macOS
  `path_helper` 重排的 Node 优先级；后续 Owner 代码仍可覆盖配置。
- 保留已有可执行 Node；缺失时仅使用已有 fnm 默认版本。尊重显式根目录、
  XDG 与原生历史目录，不安装 Node、不更改默认版本、不迁移状态。
- 基础环境只使用 Zsh builtins；Go PATH 使用 `GOBIN` 或 `GOPATH`（默认
  `~/go`），不执行 `go env`。常用工具路径重复加载不增加重复项。
- `shared.zsh` 只负责交互体验；已有补全初始化时不重复执行 `compinit`。
  交互式 fnm 激活采用上游文档形式：只要 fnm 可用就执行一次
  `fnm env --shell zsh`，因此 `fnm use` 能重定向当前版本，外部 Node 不再
  抑制激活。每个 shell 都是独立会话并指向 `default` 别名，子 shell 不继承
  父 shell 用 `fnm use` 选中的版本；本仓库不再自行恢复父版本，也不再探测
  Homebrew 前缀去补 fnm（标准 Homebrew 目录由基础环境负责）。fnm 缺失时
  保持静默，失败的输出不执行。非交互 shell 不建立会话，仍保留已有 Node
  语义。
- 新启动文件复用 Integration Block 的校验、备份、权限恢复和重跑规则；
  未选 `shell` 时不读取、校验或修改这些文件。
- 真实 Zsh 运行时测试覆盖四种启动模式、fnm 与外部 Node 的交互/非交互
  优先级、每 shell 独立会话、缺失默认版本、重复加载、根目录与 Go 配置，
  以及模拟登录 PATH 重排。
- 对本机 Owner `.zshrc` 的重复补全、旧 Go 表达式和迁移的 PATH 条目
  先备份再定点整理，不在通用安装器里删除 Owner 内容。
