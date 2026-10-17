# 04: 交互式 fnm 优先，保证 `fnm use` 可用

Status: done

按 [spec](../spec.md) 调整交互式 Node 优先级，修复新 Linux 机器上
`fnm use` 报缺环境变量的问题。

## 背景

Debian 12 容器里 `fnm use lts` 报
`We can't find the necessary environment variables to replace the Node version.`。
`fnm use` 只重定向 `$FNM_MULTISHELL_PATH`，该变量只在 `fnm env` 之后存在。
`shared.zsh` 原先的 guard 在 PATH 上已有外部 Node（基础镜像的
`/usr/local/bin/node`）时短路，所以连交互式 zsh 也从不建立 fnm 会话。

## What to build

- `shared.zsh` 的交互式激活改为：只要 `fnm` 可用就执行
  `fnm env --shell zsh`，不再因 PATH 上已有外部 Node 而跳过。
- 保留继承 fnm 版本时建立独立会话并用原生 `fnm use` 恢复父版本的逻辑。
- 非交互 shell 不建立会话，`environment.zsh` 的“已有 Node 优先”静态兜底
  不变；需要保留特定外部 Node 的 Owner 在 `.zshrc` 区块之后覆盖 `PATH`。
- README 与 spec 同步新语义。

## 验收

- [ ] 交互式 zsh 在 PATH 上已有外部 Node 时仍建立 fnm 会话，`fnm use` 可用。
- [ ] 非交互 zsh 不调用 fnm，外部 Node 保持不变。
- [ ] 继承 fnm 会话的交互子 shell 仍为独立会话并恢复父版本。
- [ ] `shell-environment-runtime`、`fnm-runtime`、`shell-runtime`、
      `integration` 等相关套件通过。

## 完成记录

- `shared.zsh` 去掉"PATH 上已有外部 Node 就跳过"的 guard，改为只要
  `command -v fnm` 成立就在交互式 shell 执行 `fnm env --shell zsh`；继承
  fnm 会话时建立独立会话并用 `fnm use --silent-if-unchanged` 恢复父版本，
  失败处理与警告保持不变。非交互 shell 仍在 `shared.zsh:12` 提前返回，
  `environment.zsh` 的“已有 Node 优先”兜底不变。
- `tests/shell-environment-runtime.sh` 按启动模式拆分断言：`-c`/`-lc`
  保留外部 Node 且不调用 fnm，`-ic`/`-lic` 断言 fnm 建立会话并覆盖外部
  Node；`tests/fnm-runtime.sh` 新增 external-node 场景，固定“存在外部
  Node 仍激活”。
- README 与本 spec 同步新语义；Owner 保留特定外部 Node 的方式是在
  `.zshrc` 区块之后覆盖 `PATH`。
- 反向验证：用 `git show HEAD:dot_plasticine/zsh/shared.zsh` 复现同一
  fixture（系统 node + fnm），HEAD 版本只调用一次 `fnm use`、不调用
  `fnm env`、`FNM_MULTISHELL_PATH` 为空；修复版本先调用 `fnm env --shell
  zsh` 再 `fnm use lts`，会话建立且不再报错。
- 验证套件全部通过：shell（389 秒）、combined-installation（60 秒）、
  integration（84 秒）、shell-runtime（25 秒）、shell-environment-runtime
  （11 秒）、fnm-runtime（4 秒）；ShellCheck、Zsh 语法检查与
  `git diff --check` 通过。
