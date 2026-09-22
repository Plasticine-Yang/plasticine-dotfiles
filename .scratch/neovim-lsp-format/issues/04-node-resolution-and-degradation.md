# 04: Node 工具链解析与降级硬化

**What to build:** 把 `--neovim` 的 Node 依赖检测从"直接看 `PATH`"硬化到能正确处理"fnm 已安装、Node 已安装但尚未进入当前 `PATH`"的情形，并让有 Node / 无 Node 两条分支的行为可被确定性验证。本切片不新增任何语言能力，只保证后续 Node 依赖切片有可靠的判定基础。

**Blocked by:** 02.

**Status:** done

- [ ] 供给步检测 `node` 与 `npm` 可用性；当 `fnm` 存在且 `node` 不在 `PATH` 时，经 `fnm env`（或等价原生解析）取得 Node bin 目录并前置到 `PATH` 后再判定。
- [ ] 有 Node 时判定为可用，不再打印降级警告。
- [ ] 无 Node 时判定为不可用，保持 02 定义的降级行为不变。
- [ ] 判定只依赖本机可观测状态，不查询任何上游元数据、不安装 Node 版本。
- [ ] 测试以受控的 fnm / node fixture 覆盖"仅 fnm""fnm+node""都没有"三种情形。
- [ ] 重复执行 `--neovim` 幂等：已就绪的环境不重复安装、不产生额外警告。

## Comments

2026-09-23: Implemented on `feat/neovim-lsp-format` in commit beda443.

- `lib/neovim-bootstrap.sh` 新增 `plasticine_neovim_fnm_node_bin`（解析 `fnm env` 的 PATH 输出，定位含 node/npm 的 bin 目录）并硬化 `plasticine_neovim_node_available`：PATH 上无 node/npm 时经 fnm 解析并前置后再判定。
- 判定只读取本机可观测状态（`command -v` 与 `fnm env`），不访问上游元数据、不安装 Node 版本；无 Node 时保持 02 的降级行为。
- `tests/neovim.sh` 以受控 fixture 覆盖 '仅 fnm'、'fnm+node'、'都没有' 三种情形，断言检测结果、mason 触发、重跑幂等且不联网。
- 验证：`tests/neovim.sh` 通过。
