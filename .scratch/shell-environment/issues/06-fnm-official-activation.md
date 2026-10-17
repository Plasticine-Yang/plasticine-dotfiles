# 06: 交互式 fnm 激活回归上游官方形式

Status: done
Blocked by: 04

按 [spec](../spec.md) 收敛 `shared.zsh` 的 fnm 初始化链路：只保留上游
文档形式的激活，删掉本仓库自加的守卫、继承会话恢复、回滚与 Homebrew
前缀探测。

## 背景

`shared.zsh` 曾用约 45 行自研逻辑实现三件事：判断是否初始化、建立会话、
并在子 shell 里恢复父 shell 的版本。这个耦合正是 04 那个 bug 的来源
（同一个 guard 同时决定"优先级"和"是否初始化"）。上游 fnm 的官方用法
只有一句 `eval "$(fnm env --shell zsh)"`。

## What to build

- `shared.zsh`：`command -v fnm` 成立时执行一次 `fnm env --shell zsh` 并
  `eval`；保留"未安装时静默""失败输出不执行并给交互式警告""不启用
  `--use-on-cd`"三条既有契约。
- 删除：继承会话检测与 `fnm use --silent-if-unchanged` 恢复、PATH 回滚、
  `fnm inherited version` 警告、Homebrew 前缀 `brew --prefix` 探测，以及
  随之消失的 `_plasticine_fnm_*` 跨文件变量。
- `environment.zsh` 的非交互静态兜底保持不变（本次不动 `.zshenv`）。
- 同步运行时测试、README 与 spec。

## 行为变化

- 交互式子 shell 不再继承父 shell 用 `fnm use` 选中的版本，而是各自指向
  `default` 别名——与 fnm 原生行为一致。
- macOS 不再为"刚 bootstrap 的 Homebrew"额外探测前缀；标准
  `/opt/homebrew/bin`、`/usr/local/bin` 仍由 `environment.zsh` 接入，
  非标准前缀下需要重开 shell（上游建议）。

## 验收

- [ ] 交互式 shell 有外部 Node 时仍建立会话，`fnm use` 可用。
- [ ] 非交互 shell 不调用 fnm，保留基础环境的已有 Node 语义。
- [ ] `fnm` 缺失静默；`fnm env` 失败时不执行输出且给出交互式警告。
- [ ] `shell-environment-runtime`、`fnm-runtime`、`shell-runtime`、
      `shell`、`integration` 通过。

## 完成记录

- `shared.zsh` 的 fnm 段从约 45 行降到 10 行：`command -v fnm` 成立时执行
  一次 `fnm env --shell zsh` 并 `eval`，失败仍给交互式警告且不执行输出。
  删除继承会话检测、`fnm use --silent-if-unchanged` 恢复、PATH 回滚、
  `fnm inherited version` 警告、Homebrew 前缀 `brew --prefix` 探测，以及
  相关的 `_plasticine_fnm_node`、`_plasticine_fnm_inherited_path`、
  `_plasticine_fnm_version`、`_plasticine_fnm_inherited_path_env` 变量。
- `environment.zsh` 未改动：非交互的静态 Node 兜底与 `.zshenv` 加载方式
  都不变。
- `tests/shell-environment-runtime.sh` 的继承场景改为断言"子 shell 建立
  独立会话、指向 default、只调用一次 `env --shell zsh`、不调用 `fnm use`"，
  非交互仍保留外部 Node；`tests/shell-runtime.sh` 删除 macOS 专用的
  Homebrew 前缀场景与对应探针行。
- 验证套件全部通过：shell（412 秒）、combined-installation（61 秒）、
  integration（83 秒）、installer（73 秒）、shell-runtime（25 秒）、
  shell-environment-runtime（13 秒）、fnm-runtime（6 秒）；ShellCheck、
  `zsh -n`、`sh -n` 与 `git diff --check` 通过。
