# 15 — 安装 uv/uvx 并集中 Python runtime

**What to build:** Owner 可以通过 Plasticine 安装 Release 精确固定的 uv，并从稳定的 uv 与 uvx 入口获得一致的集中式 Python 工具运行环境，同时保留项目环境和 uv 自己管理的内容在 Reconciliation 边界之外。

**Blocked by:** 13 — 通过 Tool Lock 安装 Lazygit

**Status:** implemented

- [x] uv 的 Tool Lock 数据为四个 Artifact Target 提供精确版本、不可变来源和 SHA-256；目标缺失、摘要不匹配或下载中断时，uv Component 明确失败且不会替换当前可用版本。
- [x] Plan 离线识别缺失、版本不符或漂移的 uv payload 以及 uv、uvx 稳定入口，完整报告所需变化且不下载、不写文件、不改 Reconciliation State。
- [x] 经授权的 Apply 原子安装并切换到精确 uv payload，创建 uv 与 uvx 两个稳定启动入口；两者从 Zsh 或非 Zsh 调用时都执行同一个受管版本。
- [x] 两个启动入口仅通过 uv 支持的机制把下载缓存、Python 安装和全局 tool roots 集中到 Plasticine Home，不注入 Reconciliation 策略，也不改变项目本地环境的位置。
- [x] uv 管理的 Python 版本、虚拟环境和已安装工具保持为 Tool-managed State；Plan、Apply、Backup 与漂移检测不读取、接管、修复或版本化这些内容。
- [x] Artifact 获取失败只使 uv Component 及其依赖结果失败，其他独立 Component 仍可继续；成功切换前保留旧 payload，干净升级不创建 Backup。
- [x] 首次 Apply 收敛后再次 Apply 不下载、不重写、不重复切换，也不改变任何 Python 或项目 Tool-managed State。
- [x] 本地 Doctor 验证精确 uv payload、uv 与 uvx 启动入口及其受管 relocation 配置；受管效果缺失或漂移时报告 unhealthy，但不枚举、运行或修改 uv 管理的 Python、环境和工具。
