# uv Python 工具链管理

新增独立的 `uv` Feature，交互菜单和 `plasticine -y --uv` 均可选择，支持 macOS/Linux，与已有 Feature 任意组合、顺序无关，不隐式选择 `shell`。

采用官方 standalone installer 把 `uv` 与 `uvx` 安装到 `~/.local/bin`：显式设置 `UV_INSTALL_DIR`，并以 `UV_NO_MODIFY_PATH=1` 阻止安装器和后续自更新修改 shell 启动文件。安装器写入的 `~/.local/bin/env` helper 会还原为 source-only 形态：去掉 `exec` 委派行与可执行位，避免它抢占 `env` 或在被 source 时替换当前 shell。安装器写入 updater receipt 后，健康的受管安装通过 `uv self update` 维护。macOS 默认没有 `sha256sum`，准备阶段用只调用 `shasum -a 256` 的临时 shim 让上游归档校验真正执行；缺少 curl、tar 或校验工具时停止。

Preview 只做本地观测并显示路线；取消、dry-run、未选择不联网、不改 uv 状态。外部归属（Homebrew、pipx 等）、不健康或无法解析/预发布版本、符号链接目标、receipt 缺失或指向其他前缀都要明确停止或走安装器修复，不降级、不另装遮蔽副本。下载、安装、自更新或最终健康检查失败返回非零，保留已完成的原生效果供重试；全部选中工具准备成功后才应用配置。

本 Feature 只维护两个命令：不安装 Python 版本、不安装 uv tool、不管理 cache/tool/python 目录、不执行 `uv python update-shell` 或 `uv tool update-shell`，也不接入 shell 补全。单选 uv 不改任何 shell 文件；共享 Zsh 配置已提供 `~/.local/bin` PATH，`--uv --shell` 可直接复用。

验证通过公开 `install.sh`/chezmoi 入口的受控安装器集成、真实 Zsh 运行时、组合安装、CLI、工作流与 Release 检查，不新增 UI 单元测试。

官方依据：[安装](https://docs.astral.sh/uv/getting-started/installation/)、[安装器选项](https://docs.astral.sh/uv/reference/installer/)、[存储目录](https://docs.astral.sh/uv/reference/storage/)、[升级 uv](https://docs.astral.sh/uv/getting-started/installation/#upgrading-uv)。
