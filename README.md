# plasticine-dotfiles

使用 [chezmoi](https://www.chezmoi.io/) 在 macOS 和 Linux 上选择并恢复个人开发环境。目前支持 Git 配置、GitHub SSH 配置、fnm、Herdr、Lazygit、Neovim 和 Zsh 环境。

## 一行安装

在交互终端中运行：

```console
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)"
```

安装器支持 macOS 和 Linux。chezmoi 的固定支持基线为 `2.72.1`：缺失或较旧的受管 direct install 会从精确的官方版本化归档安装/升级，并按随该版本审查入库的 SHA-256 验证；健康的同版本或更新 stable 版本直接复用，不查询 Release API、不下载归档，也不会降级。发布版安装器随后从同一 Plasticine Release 下载经过 SHA-256 固定的 source Git bundle，在 chezmoi 默认 source、config 和 state 路径恢复该版本；它不会通过 Git smart-HTTP clone source。Linux x86_64 会按 glibc/musl 选择该 Release 提供的对应资产；没有已审查资产的组合会停止。

chezmoi 维护和 source 获取属于安装器前置工作，会发生在 Feature 确认之前；之后取消 Feature 应用不会撤销已经完成的前置更新。外部安装归属的合格版本可以直接使用，但低于基线的版本必须由原归属更新，安装器不会覆盖它或另装一个遮蔽副本。下载、SHA-256、候选健康或发布失败都会停止安装并尽量保留原有可用命令。`PLASTICINE_CHEZMOI_BIN` 仍是测试/显式 executable override：安装器验证所需接口，但不接管、更新或联网检查这个显式路径。

选择 `neovim` 或 `shell` 时，发布版还会下载同一 Release 中固定版本的受管插件快照。首次安装从快照恢复公开插件，不执行 GitHub Git clone、fetch 或 pull，因此不要求 GitHub 用户名、Token、SSH key，也不依赖 `git-config` 或 `github-ssh`。这两个身份 Feature 仍然完全独立：没有选择就不会修改 `.gitconfig`、SSH key 或 SSH 配置。Release 资产下载本身使用匿名 HTTPS；若该网络路径不可用，安装会明确失败，不会转为凭据提示。

安装过程会选择工具、收集所需参数、自动显示变更，并在确认后应用。当前支持 Git 配置（`git-config`）、GitHub SSH、fnm（`fnm`）、Herdr（`herdr`）、Lazygit（`lazygit`）、Neovim（`neovim`）、Zsh 环境（`shell`）和默认登录 Shell（`login-shell`）；初始选择为空，不选择某个工具表示本次不处理它。

## 自动化调用

`-y` 跳过工具选择和最终确认、保留变更预览并直接应用，但不会自动选择任何工具，也不会代替 `sudo`、Homebrew 或 `chsh` 的原生凭据提示：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- -y
```

无交互配置 GitHub SSH 时必须显式提供工具和私钥：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --github-ssh --github-ssh-key /absolute/path/to/id_ed25519
```

单独应用共享 Git 配置：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --git-config
```

单独配置 Zsh 环境，或与其他工具一起配置：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --shell

sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --shell --github-ssh --github-ssh-key /absolute/path/to/id_ed25519
```

单独安装/配置 Lazygit，或与其他工具任意组合：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --lazygit
```

`--git-config`、`--github-ssh`、`--herdr`、`--fnm`、`--lazygit`、`--neovim`、`--shell` 与 `--login-shell` 可以任意组合，工具集合与顺序无关。工具选项必须配合 `-y`；不带 `-y` 使用工具选项会被拒绝并提示改用交互选择。

`--shell` 只配置 Zsh 环境，不再修改账户的默认登录 Shell。若要把已有 Zsh 设为默认登录 Shell，需在原生终端显式选择 `login-shell`；也可以同时选择两者，先完成环境配置再切换：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --login-shell

sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --shell --login-shell
```

单独保持 fnm 当前，或同时选择 shell 以复用现有守卫式激活：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --fnm

sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --fnm --shell
```

`--fnm` 不隐式选择 `shell`；所有 Feature 可以任意组合且选项顺序无关。

单独安装或更新当前稳定 Neovim、迁移配置并恢复该 Plasticine Release 的插件快照：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --neovim
```

`--neovim` 不会隐式选择 shell、fnm 或 Git 配置，也可以和现有 Feature 任意组合。

单独安装或更新 Herdr，也可以把它与其他 Feature 任意组合：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --herdr
```

`--herdr` 不依赖 `--shell`；所有 Feature 选项的顺序都不影响选择结果。

已有不同的 `~/.ssh/id_github` 时，自动化调用还需要显式传入 `--replace-github-ssh-key`。可通过 `--github-ssh-test` 在应用后测试连接。`-y` 不会启用 chezmoi 的强制覆盖，配置冲突仍会停止安装，也不会代替 Homebrew、`sudo` 或 `chsh` 的原生凭据提示。

## 日常使用

安装后可以直接使用 chezmoi：

```sh
chezmoi diff
chezmoi apply
chezmoi update
```

重新选择工具或更换私钥时，再运行一行安装命令或本地 `install.sh`。不选择某个工具表示本次不处理它，不会自动卸载工具或删除已有配置。

一行 Release 安装固定到发布时验证过的 source 与插件版本，后续直接运行 `chezmoi apply` 也会识别持久 snapshot 标记并继续做离线运行时验证。`chezmoi update` 以及插件管理器的原生更新命令属于安装后的显式 moving-upstream 操作，可能按本机 Git/网络策略访问 GitHub。它们不再是新机器完成 Release 安装的前提。

如果默认的 `~/.local/share/chezmoi` 已属于其他仓库，或者当前 source 有未提交修改，安装器会停止，不会覆盖或清理它。

## 本地开发

从 checkout 运行同一套流程：

```sh
PLASTICINE_DOTFILES_REPO_URL="$PWD" ./install.sh
```

## GitHub SSH 行为

- 将用户指定的私钥复制到 `~/.ssh/id_github`，源文件保持不变。
- 将 GitHub 配置写入 `~/.ssh/config.d/00-plasticine-github.conf`。
- 只在 `~/.ssh/config` 顶部维护一个带标记的 `Include` 区块，其余内容保持不变。
- 首次接管已有 `~/.ssh/config` 时备份为 `~/.ssh/config.plasticine-backup-before-managed`。
- 替换已有 `~/.ssh/id_github` 前展示新旧公钥指纹并要求确认，替换时保留带时间戳的备份。
- 检测到已有 GitHub 用户、主机或私钥规则时停止，不自动覆盖冲突配置。
- `~/.ssh` 和 `config.d` 权限为 `700`，配置及私钥权限为 `600`。
- 私钥内容不会写入仓库、chezmoi 配置或 diff；本机 chezmoi 配置仅记录源路径和公钥指纹。

连接测试是可选项，会运行 `ssh -T git@github.com`，并使用 OpenSSH 的 `accept-new` 主机密钥策略。

## Git 配置（`--git-config`）

该 Feature 整体管理 `~/.gitconfig`，设置共享身份 `plasticine <975036719@qq.com>`、默认初始分支 `main` 和 `pull.rebase = true`，并把 `~/.gitconfig.local` 作为最后一个 include。公司或机器专属身份可写在这个本地 override 中，其值会按 Git 原生优先级覆盖共享值。Plasticine 不读取、预览、备份、创建、合并或改写 `~/.gitconfig.local`。

替换已有普通 `~/.gitconfig` 前，Preview 会展示整个受管文件差异，并在 `~/.plasticine/backups/git-config/` 创建权限为 `0600` 的原文件备份；备份目录为 `0700`，目标原有权限会在应用后恢复。内容相同的重跑不会改写文件或重复备份。目标或备份父路径是符号链接、文件/目录类型不符时，应用会在任何已选工具变化前停止；修复路径后重跑即可。

`--git-config` 与 GitHub SSH 完全独立，不安装或更新 Git、OpenSSH，不添加凭据存储、URL rewrite，也不清理旧 checkout 或任何本地 Git 数据。

## Lazygit（`--lazygit`）

Lazygit 的固定支持基线为 `0.65.1`。确认 apply 后，缺失或较旧的受管 direct install 才下载 macOS/Linux、`x86_64`/`arm64` 对应的精确官方版本化归档，并按随该版本审查入库的 SHA-256 验证归档、成员和候选版本，再以 `0755` 原子发布到 `~/.local/bin/lazygit`。健康的同版本或更新 stable 版本直接复用，不查询 Release API、不下载归档，也不会降级；Preview、dry-run、取消和未选中 Feature 同样不下载。该 digest 与归档处于同一 GitHub Release 信任边界，不是独立签名。此路线不调用 Homebrew、APT、`sudo`、`go install` 或第三方安装器，也不需要凭据或终端提示。

不健康、无法解析版本、prerelease/custom 或位于其他路径且低于基线的安装不会被静默替换或用第二份安装遮蔽；请使用其原有 owner 更新，或明确移除该安装后重试。下载、校验、解包、候选健康、竞态检测或最终版本校验失败都会使本次 Feature 失败，即使旧二进制仍能运行；候选准备失败保留活动安装。fresh publication 后的最终检查失败也保留已发布路径并给出修复/重试指引，不依据早先归属自动删除它。

下载、Release 元数据、校验、解压、发布或安装后健康检查失败时不会改用其他安装路线，也不会应用别名。一次调用选择多个工具时，会先完成所有工具准备，再开始任何受管配置的备份、权限调整或写入；若较后的工具准备失败，较早完成的健康工具会保留，但本次配置仍保持未应用。修复网络、上游资源或本机文件系统问题后可以重跑同一命令，从观测到的健康状态继续。如果发布后的健康检查失败，报错中所列路径会被保留：若它已被其他 Owner 替换，应修复该 Owner 文件；若它仍是本次发布的不健康文件，必须先修复或删除它，再重跑。

`--lazygit` 只在 Owner 控制的 `~/.zshrc` 中维护以下区块，并与 `shell` 区块共用同一个组合与备份流程：

```zsh
# >>> Plasticine lazygit >>>
alias lg='lazygit'
# <<< Plasticine lazygit <<<
```

缺失区块按固定工具顺序插到文件开头，已有合法区块原地更新；区块外字节和原文件权限保持不变。一次 apply 即使多个区块同时变化，也只在 `~/.plasticine/backups/integration-blocks/` 生成一个权限为 `0600` 的 `.zshrc` 全量备份；满足状态的重跑不会改写或新增备份。所有选中区块在任何工具安装前验证，所有选中工具健康后才允许备份和配置应用。

Lazygit 的配置、缓存、日志、仓库状态和 `~/.config/lazygit` 都不归 Plasticine 管理，也不会被检查、导入、备份或删除；旧 `~/.plasticine-dotfiles` 及其运行时状态同样不会清理。安装路线不修改 `PATH`：只选 Lazygit 的 Owner 需要自行确保 `~/.local/bin` 已在 `PATH` 中；同时选择 `shell` 时，共享 Zsh 配置会提供现有的 `~/.local/bin` 默认值。

## fnm（`--fnm`）

每次 apply 都建立当次当前目标。macOS 先运行 `brew update` 刷新元数据，以 Homebrew 最新可用的稳定 `fnm` formula 为目标，只在缺失时 `brew install fnm`、过期时 `brew upgrade fnm`；formula 可能落后于上游 Release，因此只称为“Homebrew 当前”，不宣称等于上游最新。缺少 Homebrew 时复用经审查的官方 bootstrap：它需要原生终端，Homebrew 可能要求管理员凭据或 Apple Command Line Tools，`-y` 不会代答。

Linux 完整下载 `https://fnm.vercel.app/install` 后才执行，传入 `--skip-shell --install-dir <临时候选目录>`，不传固定 `--release`，也不回退到 APT、Homebrew 或其他包管理器。候选先通过 `fnm --version` 健康/稳定版本检查，再发布到 `~/.local/bin/fnm`；首次发布 no-clobber，直接安装更新会在替换前重验目标。官方脚本及其后续下载属于同一上游信任边界，Plasticine 没有额外的独立签名验证。下载、脚本、元数据、Homebrew、候选、发布或最终健康失败都会返回非零；准备失败会保留原有可用命令，原生工具已经完成的效果则保留并可安全重跑。

已是当前目标时不会替换命令。稳定版本比当前目标更新、预发布/自定义/无法解析的版本、不健康命令会拒绝降级或接管；允许路线之外的旧 owner 必须通过原 owner 更新，不会在 `~/.local/bin` 另装遮蔽副本。Preview 只报告本地观测、路线、后续网络和权限影响；目标查询和工具变更只在确认后的 apply 发生，取消与 dry-run 不执行它们。

只选择 `--fnm` 不读取或编辑 `.zshrc`，也不添加 shell integration。请自行确保 `~/.local/bin` 在 `PATH`，并按需配置原生 `fnm env --shell zsh` 激活；同时选择 `--shell` 时会复用已有的唯一守卫式激活，失败输出不会被 `eval`，且不会启用 `--use-on-cd`。安装只维护 manager：Node 版本、默认 Node、项目版本声明、`FNM_DIR` 和 fnm 原生 runtime/state 都不会被检查、迁移或修改。

## Neovim（`--neovim`）

Neovim 编辑器发行版的固定支持基线为 `0.12.5`。缺失或较旧的受管 direct install 才下载 macOS/Linux、`x86_64`/`arm64` 对应的精确官方版本化 `tar.gz`，把完整发行版发布到 `~/.local/opt/neovim`，并以 `~/.local/bin/nvim` 链接提供命令。健康的同版本或更新 stable 版本直接复用，不查询 Release API、不下载编辑器归档，也不会降级。该路线不会调用 Homebrew、APT、Cargo、AppImage、`sudo` 或第三方安装器；缺少 `curl`、`tar` 或 SHA-256 工具会给出指引并停止。只选择 Neovim 不会编辑 shell 启动文件，因此 Owner 仍需确保 `~/.local/bin` 在 `PATH`。

四个官方资产的 SHA-256 随 `0.12.5` 一并审查入库；Plasticine 在安全检查 archive 成员后验证 digest、完整 runtime 布局、候选版本以及候选能否加载自身 runtime，再发布整个目录。该 digest 与 archive 都处于 GitHub Release 的同一信任边界，并不是独立签名。fresh 发布保持 no-clobber；由上述路径管理的旧稳定版本在候选验证后重验活动目标，再替换完整发行版。合格版本不重复下载或替换 distribution，但仍验证插件运行时。

位于其他路径且达到基线的稳定编辑器可以继续使用且不会被修改。其他 owner 的旧版本以及不健康/无法比较/预发布/自定义版本会被拒绝；安装器不会调用其包管理器、降级、切换 channel 或另装遮蔽副本。下载、digest、解包、候选 runtime 或发布失败发生在配置写入前，并保留旧 installation；若完整 distribution 已发布而命令链接或最终健康检查失败，诊断会明确保留状态，Owner 修复冲突后可重跑。

Plasticine 只整体管理以下九个文件：

- `~/.config/nvim/init.lua`
- `~/.config/nvim/lua/basic.lua`
- `~/.config/nvim/lua/keybindings.lua`
- `~/.config/nvim/lua/colorschema.lua`
- `~/.config/nvim/lua/plugins.lua`
- `~/.config/nvim/lua/plugins-config/neoscroll.lua`
- `~/.config/nvim/lua/plugins-config/nvim-tree.lua`
- `~/.config/nvim/lua/plugins-config/surround.lua`
- `~/.config/nvim/lua/plugins-config/toggleterm.lua`

变更文件在写入前备份到 `~/.plasticine/backups/neovim/`，原 mode 在 apply 后恢复；内容相同不会重复写入或备份。其他配置文件与 `lazy-lock.json` 不会被 Plasticine 接管。`init.vim`、符号链接/非普通目标、`NVIM_APPNAME` 或非默认 `XDG_CONFIG_HOME` 会被明确拒绝，避免修改一个不会被目标编辑器使用的配置树。

配置保留 legacy 的编辑偏好、Tokyo Night、平滑滚动、surround、自动配对、Hop、nvim-tree 和浮动/水平/垂直终端快捷键，并适配快照中审查过的插件接口。发布版在配置应用前从 Release 快照恢复 lazy.nvim 与全部声明插件，应用后直接验证配置启动、文件树命令和终端函数，不运行 `Lazy! sync`。快照 checkout 保留官方 `origin`，并带有 Plasticine snapshot 标记；后续新版 Plasticine Release 可以安全推进这些快照。已存在且由 lazy.nvim/Owner 管理的 checkout 不会被接管或替换。

从本地 checkout 运行开发安装时仍使用 lazy.nvim 的原生 moving-upstream 流程，并显式执行 `Lazy! sync`；Git 终端提示会被禁用，任何插件错误都会使安装返回非零。`lazy-lock.json`、Owner checkout、cache 和 state 始终是 lazy.nvim/Neovim 的原生状态。快照恢复、原生同步或运行时检查失败时，已经生成的配置备份、已应用配置和已完成的原生效果会保留；修复报告的问题后重跑即可，不会伪装成全事务回滚。

## Herdr（`--herdr`）

每次确认应用后，Plasticine 都从 `https://herdr.dev/latest.json` 解析当次稳定目标；Preview 和取消不会查询该目标。Herdr 缺失时，会先完整下载 `https://herdr.dev/install.sh`，令官方脚本通过 `HERDR_INSTALL_DIR` 安装到私有临时目录。官方脚本负责平台选择、下载和 manifest SHA-256 校验；该校验与下载元数据同属 `herdr.dev` 信任边界，不是独立签名。候选通过安全的 `herdr --version` 检查且与稳定目标一致后，才以原子 no-clobber 方式发布到 `~/.local/bin/herdr`。

`~/.local/bin/herdr` 的稳定 direct install 过期时，Plasticine 调用原生命令 `herdr update`，随后再次核对版本。不会传 `--handoff`，不会替 Herdr 回答确认、停止 server/session 或把 `-y` 当作 native process-control 授权；若旧 server 需要人为干预，更新失败并提示在终端中重试。当前稳定版本保持不变。PATH 中其他归属的当前版本可以保留；过期的 Homebrew、mise、Nix 或其他外部归属必须由其 Owner 更新，Plasticine 不会覆盖或另装副本。preview/custom channel、异常版本、损坏命令以及比 stable manifest 更新的版本也不会被静默切换或降级。

此 Feature 只维护命令，不启动 Herdr UI/server、不创建 session、不安装 agent integration，也不创建、读取、迁移或清理 Herdr 配置、插件、缓存和 session 数据。它不创建 alias 或修改 shell 文件；只选 Herdr 时，Owner 需自行将 `~/.local/bin` 加入 `PATH`，同时选择 `shell` 时可复用现有共享 PATH。元数据、官方 installer、上游校验、候选健康、native update、发布或最终目标检查失败都返回非零；当前已有命令和 native state 尽量保留，可排除提示的问题后安全重跑。

## Zsh 环境（`--shell`）

`--shell` 准备一套可用的 Zsh 体验：Zsh 本体保留系统/APT 例外；发布版从固定的 Release 快照恢复 Antidote（Linux）、Powerlevel10k 和声明的插件，不在安装过程中对这些公开仓库执行 Git 更新，最后才尝试切换登录 shell。

Shell 原生安装路线支持 macOS 14+、Debian 12+、Ubuntu 24.04+ 的 x86_64/arm64；Debian 12 与 13、Ubuntu 24.04 是明确支持的 Linux 基线，更新版本采用 best-effort。其他 Linux 发行版仅在已有依赖满足时尝试配置，不提供 APT 或 Linux Homebrew 回退。低于版本下限时，即使已有 Zsh 也会拒绝本次 Shell 选择；可重新运行并取消选择 `shell`，其他工具仍按各自的支持条件检查。此限制不是所有工具共享的最低系统要求。

### 受管路径

| 路径 | 归属 |
| --- | --- |
| `~/.plasticine/zsh/shared.zsh` | chezmoi 整体管理的共享片段 |
| `~/.zsh_plugins.txt` | chezmoi 整体管理的插件声明 |
| `~/.p10k.zsh` | chezmoi 整体管理的 Powerlevel10k 偏好 |
| `~/.zshrc` | Owner 控制；Plasticine 只维护带标记的区块 |

`~/.zshrc` 中最多只有一个标记区块：

```zsh
# >>> Plasticine shell >>>
if [ -r "$HOME/.plasticine/zsh/shared.zsh" ]; then
    if ! . "$HOME/.plasticine/zsh/shared.zsh"; then
        if [[ -o interactive ]]; then
            print -ru2 -- "plasticine: shared shell configuration unavailable"
        fi
    fi
fi
# <<< Plasticine shell <<<
```

缺少区块时插入到文件开头，已存在时原地替换，区块以外的每个字节都会保留。重复、嵌套、顺序颠倒或不完整的标记会让本次安装停止，并且不修改任何文件。目标是符号链接、目录、FIFO 等非普通文件，或 `~/.plasticine`、`~/.plasticine/zsh` 不是普通目录时同样拒绝执行；非交互选择下这些目标也会在第一个工具改动之前完成校验。

被替换的已有文件会通过共享的 whole-file 保护流程先备份到 `~/.plasticine/backups/shell/`（权限 `600`，目录 `700`），并保留原有文件权限；同一保护流程也用于 `~/.zshrc`，方便后续受管配置复用相同契约。中断后遗留的权限恢复记录会在安全重试时处理。已经满足的安装重复运行不会产生新的写入或备份。

### Owner 扩展点

- `~/.zsh_plugins.local.txt`：可选的 Owner 插件声明，在受管声明之后加载；Plasticine 不会创建、替换、备份或删除它。
- `~/.zshrc` 中标记区块以外的内容完全由 Owner 控制；区块之后的代码仍会执行，并可以覆盖共享默认值（例如 `PATH`）。
- `shared.zsh` 只提供默认值，可被后续 Owner 代码覆盖；`~/.p10k.zsh` 可以用 `p10k configure` 重新生成，但它是整体受管文件，下一次 `chezmoi apply` 会用仓库版本替换它（替换前先备份）。

### 工具归属

- macOS 使用系统 Zsh；Debian/Ubuntu 使用已有的健康 Zsh，缺失时通过审查过的 APT 路径安装 `zsh`。
- macOS 的 Antidote 由 Homebrew 管理：每次选择 shell 时先刷新 metadata，只安装或升级 `antidote` formula，绝不执行 broad upgrade。Debian/Ubuntu 的首次发布版安装从固定快照恢复官方 Git checkout（`~/.antidote`）；后续 Plasticine Release 可以推进带 snapshot 标记的旧快照。已存在的 Owner checkout 不会被 reset、接管或替换。
- 发布版从同一固定快照恢复 Powerlevel10k 与受管插件，随后仅用 Antidote 重新生成 bundle，不运行 `update --bundles`。从本地 checkout 运行开发安装时仍使用原生 moving-upstream 路线：Linux Antidote 执行 `git pull --ff-only`，插件执行 `antidote update --bundles`。这些 Git 操作禁用终端凭据提示，并在失败时返回非零。同步使用受管声明文件但不 source Owner 的 `~/.zshrc`。
- 已存在但不健康的 Zsh、Antidote、Git、Homebrew 或 Powerlevel10k 会被原样保留并以可操作的错误结束，不会更换安装归属，也没有自动回退路径。metadata 查询、快照恢复、开发模式原生更新、bundle 生成或最终运行时检查失败同样返回失败；已完成的配置和 native state 会保留，修复报告的问题后重跑即可继续。
- Antidote 自己拥有它的 checkout、生成的 bundle、插件克隆、缓存、快照、补全 dump 和编译文件；`~/.zsh_plugins.local.txt` 也属于 Owner。Plasticine 既不管理、也不备份或删除这些运行时状态。
- `fnm` 只做守卫式激活：已经安装时执行 `fnm env --shell zsh`；命令失败时不会执行它的输出，只会以交互式警告提示，也不会安装、升级或迁移 fnm 及其状态。未安装 fnm 时保持静默。macOS 上若 fnm 只存在于 Homebrew 前缀中，仅在这种情况下把该前缀的可执行目录加入 `PATH`，不移动任何文件。Zellij 别名仍属于未来迁移。

### 包管理器与凭据影响

- Debian/Ubuntu：`sudo apt-get update` 与 `sudo apt-get install -y --no-upgrade <packages>`；只有这两个子命令使用 `sudo`。没有可用终端时改用 `sudo -n`，需要凭据时会失败并提示在原生终端重试。
- macOS：缺少 Homebrew 时先预览，再用官方安装脚本引导 Homebrew；这一步需要原生终端，而且 Homebrew 自身可能要求管理员凭据或 Apple Command Line Tools。Plasticine 不会用 `sudo bash` 执行它。
- `--yes` 只跳过 Plasticine 自己的最终确认，不会代替 Homebrew、`sudo` 或 `chsh` 的原生提示；无法提供凭据时安装以错误结束，而不是伪造输入。
- 预览先列出所选路径、Release 快照或开发模式 Antidote/插件更新意图、网络访问、包管理器改动、可能的提权以及将要执行的 `chsh` 命令，然后才请求确认。取消确认不会恢复插件快照、查询 shell upstream 或运行 native updater：已经恢复的 chezmoi source 和已记录的工具选择会保留，但不会写入 `~/.zshrc`、`~/.zsh_plugins.txt`、`~/.p10k.zsh` 或 `~/.plasticine`，也不会调用任何安装命令或 `chsh`。
- 上游安装脚本的行为部分不透明；失败时直接报错，不会自动改用其他路径。

### 默认登录 Shell（`login-shell`）

- `login-shell` 是独立、默认不选的工具；仅选择 `shell` 不查询账户登录 Shell，也不调用 `chsh`。已有 `tools = ["shell"]` 的配置不会自动启用新工具。
- 单独选择 `login-shell` 只检查已有 Zsh 并切换账户，不安装工具、不下载插件、不修改 `.zshrc` 或其他 Shell 配置；缺失或不健康的 Zsh 会明确报错，需先安装或同时选择 `shell`。macOS 使用系统 `/bin/zsh`，Linux 使用 PATH 中的 Zsh。
- 登录 shell 从原生账户数据库读取（不是 `$SHELL`）；Debian/Ubuntu 上 `/bin/zsh` 与 `/usr/bin/zsh` 视为同一个 Zsh。
- 与其他工具组合时，在所选工具准备、配置和插件同步成功后才尝试 `chsh -s <zsh 绝对路径>`；需要原生终端，系统可能要求当前账户密码，不会使用 `sudo chsh`，也不会修改 `/etc/shells`。
- `chsh` 失败（密码错误、账户策略、没有终端等）会保留已有工具与配置，本次安装返回失败；在原生终端里仅选择 `--login-shell` 即可只重试这一步。
- 登录 shell 已经正确时不会调用 `chsh`，此时 `$SHELL` 的值不影响判断。

### 与旧仓库的关系

- `--shell` 不读取也不执行 `~/.plasticine-dotfiles` 中的任何文件。
- 本功能不删除 `~/.plasticine-dotfiles`，也不迁移或清理任何旧运行时状态（生成的 `.zsh_plugins.zsh`、Antidote 插件克隆、缓存、快照、补全 dump、编译文件、`~/.zsh_plugins.local.txt` 等）。清理旧仓库需要单独的、显式的迁移设计。
- 不选择 `shell` 时不会探测 Antidote 或改动它的配置和插件；独立的 `login-shell` 只负责 Zsh 检查和账户登录 Shell。

## 本地验证

测试全部运行在临时目录，不会修改真实的 `~/.ssh`、`~/.zshrc` 或 `~/.plasticine`，也不会真的调用包管理器、`sudo`、`brew` 或 `chsh`：

```sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/integration.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/combined-installation.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/chezmoi.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/installer.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/shell.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/lazygit.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/lazygit-runtime.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/fnm.sh
./tests/fnm-runtime.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/neovim.sh
./tests/neovim-runtime.sh
PLASTICINE_LIVE_NEOVIM_SMOKE=1 ./tests/neovim-live.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/herdr.sh
./tests/shell-runtime.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/release.sh
./tests/release-payload.sh
./tests/test-runner.sh
./tests/ci-gate.sh
./tests/workflows.sh
```

`tests/combined-installation.sh` 通过真实 `install.sh` 与 chezmoi 入口覆盖八个 Feature 的交互/非交互全选、顺序无关性、跨工具 target 更新、配置前准备、配置后原生同步、取消、dry-run、部分失败与安全重试；各 Feature 的网络、包管理器、完整发行版、owner、完整性与竞态细节仍由其专项 suite 覆盖。`tests/shell.sh` 覆盖安装器侧的 Zsh 选择、工具准备、`shell` / `login-shell` 独立选择、登录 Shell 切换、失败重试与运行时状态隔离；`tests/lazygit.sh` 用受控 release、网络、平台和文件系统 fixture 覆盖 Lazygit 路线且不会访问真实网络；`tests/fnm.sh` 覆盖 Linux 官方脚本候选发布和 macOS Homebrew currency 路线；`tests/lazygit-runtime.sh` 与 `tests/shell-runtime.sh` 使用真实 Zsh，后者包含受控 fnm 的成功/失败激活、Owner 后续代码继续执行和单次初始化验证。`tests/neovim.sh` 使用受控 Release 与编辑器边界覆盖公开 chezmoi 入口；`tests/neovim-runtime.sh` 在一次性 HOME 中用真实 Neovim 和本地受控插件 fixture 验证启动、快捷键、文件树与终端，routine 测试不依赖 live Release；显式设置 `PLASTICINE_LIVE_NEOVIM_SMOKE=1` 后运行 `tests/neovim-live.sh`，可另行使用当前 upstream 插件执行 smoke；Zsh runtime 套件需要本机存在 `zsh`。CI 通过 `scripts/run-test.sh` 单独运行每个 suite：基础设施契约测试最长 30 秒，常规 suite 最长 180 秒，Shell 综合 suite 最长 300 秒；超时会终止整个测试进程组并直接报告 suite 名称。

## 发布

本仓库使用独立的 SemVer 版本线，从 `v0.1.0` 开始。日常提交和 Pull Request 会在 Ubuntu 与 macOS 上执行完整测试，并在 Debian 12 的 x86_64/arm64 容器中执行 Shell 和安装器回归，以及真实 APT Zsh、Antidote 和当前插件的安装、启动与重跑检查。Debian 容器使用一次性非 root 用户，登录 shell 预设为目标路径；真实 `chsh` 账户认证仍需在独立 Debian 终端验证，不能由容器测试替代。稳定版本只能从 GitHub Actions 的 `Release` workflow 手动触发，并输入 `vMAJOR.MINOR.PATCH` 格式的版本号。

发布流程先等待并复用触发时 `main` commit 的成功 push CI，精确核对 Ubuntu、macOS 和 Debian x86_64/arm64 四个 job；不会在 Release workflow 中重复执行完整测试矩阵。随后通过 `scripts/release-gate.sh` 统一构建并验证 `install.sh`、`plasticine-source.bundle`、`plasticine-managed-plugins.tar.gz` 和 `SHA256SUMS`，先创建 draft Release，核对 tag、commit 与四个附件后再发布。该门禁可从非 Git 工作目录运行，并支持相对输出目录，避免本地与 GitHub Actions 使用不同的发布路径。发布版安装器固定到该 Release 的完整 commit，并内含 source/plugin payload 与 chezmoi `2.72.1` 的版本/完整性数据；随 source 固定的 Lazygit `0.65.1`、Neovim `0.12.5` 与 Neovim/Zsh 插件快照也只会随新的 Base Dotfiles Release 前进。因此历史 Release 的安装内容不会随上游新版本或 `main` 推进而改变，而顶层 `/releases/latest/download/install.sh` 仍只负责选择最新 Base Dotfiles 稳定版本。

发布前应在仓库设置中将 `CI / Test (ubuntu-24.04)`、`CI / Test (macos-14)`、`CI / Debian 12 shell (ubuntu-24.04)` 和 `CI / Debian 12 shell (ubuntu-24.04-arm)` 配置为 `main` 的 required checks，并启用 GitHub immutable releases。CI 和 Release workflow 中使用的第三方 Actions 固定到完整 commit，由 Dependabot 每月提出更新。
