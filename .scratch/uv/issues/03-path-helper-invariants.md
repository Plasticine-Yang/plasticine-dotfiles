# 还原安装器的 PATH helper 不变量

Status: done
Type: task
Blocked by:

## 验收条件

- 安装或自更新成功后，若 `~/.local/bin/env` 被改成可执行、或包含以 `exec` 开头的委派行，Feature 把它还原成 source-only 形态：删掉这些 `exec` 行与可执行位，其余内容保持不变。
- 已经符合安装器形态的 helper 不被重写，逐字节保持原样。
- helper 是符号链接或非普通文件时停止并给出可操作错误，不修改它。
- `tests/uv.sh` 覆盖还原、保持、非普通文件拒绝三种情况，并断言 source 该 helper 不会再替换当前 shell。

## 背景

官方安装器把 `env` 写进 `~/.local/bin` 作为 source-only 的 PATH helper。一旦它被改成可执行并被放到 PATH 前面，`env` 就会解析到这个脚本；再叠加一行 `exec /usr/bin/env "$@"`，被 shell 启动文件 source 时会直接替换当前 shell，导致其后所有 PATH 追加都不再生效，而把它当命令执行的调用方则依赖参数透传。两个后果互相拉扯，任何只手改一侧的修法都会让另一侧失效，因此由 Feature 保证这两个不变量。

## Comments

- 2026-10-20：在 `plasticine_uv_prepare` 收尾处加入 `plasticine_uv_restore_path_helper`，安装/修复/自更新三条路线都会还原 `env` helper 的两个不变量；`mv` 加入准备阶段的必需命令。README 与 uv spec 同步说明例外范围。
- 验证：`./scripts/check.sh uv uv-runtime installer cli combined-installation` 全部通过；`tests/uv.sh` 新增还原、保持、非普通文件拒绝三个场景，并断言 source helper 不再替换当前 shell。另用本机被改坏的真实 helper（755 + `exec /usr/bin/env "$@"`）直接调用还原函数：权限降为 644、`exec` 行消失、重复执行不再改写，其余内容逐字节保留。
