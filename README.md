# plasticine-dotfiles

使用 [chezmoi](https://www.chezmoi.io/) 在 macOS 和 Linux 上选择并恢复个人开发环境。目前支持 GitHub SSH 配置、fnm、Lazygit、Neovim 和 Zsh 环境。

## 一行安装

在交互终端中运行：

```console
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)"
```

安装器支持 macOS 和 Linux。每次调用都会先查询 chezmoi 官方 GitHub Release 的最新稳定版本：缺失时把完整校验过的归档安装到 `~/.local/bin/chezmoi`，该直接安装过期时安全更新，已经是目标版本时不替换。然后安装器使用 chezmoi 的默认 source、config 和 state 路径。

chezmoi 维护和 source 获取属于安装器前置工作，会发生在 Feature 确认之前；之后取消 Feature 应用不会撤销已经完成的前置更新。外部安装归属的当前版本可以直接使用，但过期版本必须由原归属更新，安装器不会覆盖它或另装一个遮蔽副本。元数据、下载、SHA-256、候选健康或发布失败都会停止安装并尽量保留原有可用命令。`PLASTICINE_CHEZMOI_BIN` 仍是测试/显式 executable override：安装器验证所需接口，但不接管、更新或联网检查这个显式路径。

安装过程会选择工具、收集所需参数、自动显示变更，并在确认后应用。当前支持 GitHub SSH、fnm（`fnm`）、Lazygit（`lazygit`）、Neovim（`neovim`）和 Zsh 环境（`shell`）；初始选择为空，不选择某个工具表示本次不处理它。

## 自动化调用

`-y` 禁止所有交互、保留变更预览并直接应用，但不会自动选择任何工具：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- -y
```

无交互配置 GitHub SSH 时必须显式提供工具和私钥：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --github-ssh --github-ssh-key /absolute/path/to/id_ed25519
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

`--lazygit`、`--shell` 与 `--github-ssh` 可以任意组合，工具集合与顺序无关。工具选项必须配合 `-y`；不带 `-y` 使用工具选项会被拒绝并提示改用交互选择。

单独保持 fnm 当前，或同时选择 shell 以复用现有守卫式激活：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --fnm

sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --fnm --shell
```

`--fnm` 不隐式选择 `shell`；所有 Feature 可以任意组合且选项顺序无关。

单独迁移已有的当前稳定 Neovim 配置并更新插件：

```sh
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)" -- \
  -y --neovim
```

`--neovim` 不会隐式选择 shell、fnm 或 Git 配置，也可以和现有 Feature 任意组合。

已有不同的 `~/.ssh/id_github` 时，自动化调用还需要显式传入 `--replace-github-ssh-key`。可通过 `--github-ssh-test` 在应用后测试连接。`-y` 不会启用 chezmoi 的强制覆盖，配置冲突仍会停止安装，也不会代替 Homebrew、`sudo` 或 `chsh` 的原生凭据提示。

## 日常使用

安装后可以直接使用 chezmoi：

```sh
chezmoi diff
chezmoi apply
chezmoi update
```

重新选择工具或更换私钥时，再运行一行安装命令或本地 `install.sh`。不选择某个工具表示本次不处理它，不会自动卸载工具或删除已有配置。

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

## Lazygit（`--lazygit`）

每次确认 apply 都会查询 `jesseduffield/lazygit` 的最新官方 stable GitHub Release；Preview、dry-run 和取消不会查询 release metadata。缺失时，Plasticine 下载当前 macOS/Linux、`x86_64`/`arm64` 对应归档及同一 Release 的 `checksums.txt`，验证 SHA-256、归档成员与候选版本后，以 `0755` 原子 no-clobber 发布到 `~/.local/bin/lazygit`。已由该路径直接安装的旧 stable 版本会在候选完整验证后重新校验活动目标，再以同目录原子替换升级；当前版本只查询 metadata，不下载或替换归档。该校验和与归档处于同一 GitHub Release 信任边界，不是独立签名。此路线不调用 Homebrew、APT、`sudo`、`go install` 或第三方安装器，也不需要凭据或终端提示。

不健康、无法解析版本、prerelease/custom、比当前 stable target 更新或位于其他路径的旧安装不会被静默替换、降级或用第二份安装遮蔽；请使用其原有 owner 更新，或明确移除该安装后重试。metadata、下载、校验、解包、候选健康、竞态检测或最终版本校验失败都会使本次 Feature 失败，即使旧二进制仍能运行；候选准备失败保留活动安装。fresh publication 后的最终检查失败也保留已发布路径并给出修复/重试指引，不依据早先归属自动删除它。

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

本增量只支持已经安装并可运行、且版本恰好等于 Neovim 官方最新稳定 Release 的编辑器。Preview 只做本地目标校验并说明 apply 时的网络与更新动作，不查询 Release；确认 apply 后才查询 `api.github.com/repos/neovim/neovim/releases/latest`。缺失、损坏、预发布、无法比较或过期的编辑器会在配置应用前失败，并提示等待/使用 ticket 13 的官方预编译 archive 路线；这里不会调用 Homebrew、APT 或安装单独的可执行文件。

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

配置保留 legacy 的编辑偏好、Tokyo Night、平滑滚动、surround、自动配对、Hop、nvim-tree 和浮动/水平/垂直终端快捷键，但移除了 plugin tag/commit pin，并适配当前插件接口。lazy.nvim 从其 moving `stable` 分支 bootstrap；每次 apply 都显式执行 `Lazy! sync`，在相同的隔离 HOME/native XDG data、cache 和 state 路径中完成插件安装与更新，然后验证配置启动、文件树命令和终端函数。`lazy-lock.json`、checkout、cache 和 state 始终是 lazy.nvim/Neovim 的原生状态。

插件同步发生在九文件配置应用之后。同步或运行时检查失败时命令返回非零，已经生成的配置备份、已应用配置和 lazy.nvim 已完成的原生效果会保留；修复网络、插件或运行时错误后重跑即可，不会伪装成全事务回滚。

## Zsh 环境（`--shell`）

`--shell` 准备一套可用的 Zsh 体验：准备 Zsh 与 Antidote、通过 Antidote 获取 Powerlevel10k、写入受管配置，最后才尝试切换登录 shell。

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
- Antidote 使用已有的健康安装；缺失时 macOS 使用 Homebrew，Debian/Ubuntu 使用官方 Git checkout（`~/.antidote`）。
- Powerlevel10k 通过 Antidote 的插件机制获取（`antidote bundle romkatv/powerlevel10k kind:clone`）；Plasticine 不复制、不固定它的 checkout。
- 已存在但不健康的 Zsh、Antidote、Git、Homebrew 或 Powerlevel10k 会被原样保留并以可操作的错误结束，不会更换安装归属，也没有自动回退路径。
- Antidote 自己拥有它的 checkout、生成的 bundle、插件克隆、缓存、快照、补全 dump 和编译文件；`~/.zsh_plugins.local.txt` 也属于 Owner。Plasticine 既不管理、也不备份或删除这些运行时状态。
- `fnm` 只做守卫式激活：已经安装时执行 `fnm env --shell zsh`；命令失败时不会执行它的输出，只会以交互式警告提示，也不会安装、升级或迁移 fnm 及其状态。未安装 fnm 时保持静默。macOS 上若 fnm 只存在于 Homebrew 前缀中，仅在这种情况下把该前缀的可执行目录加入 `PATH`，不移动任何文件。Zellij 别名仍属于未来迁移。

### 包管理器与凭据影响

- Debian/Ubuntu：`sudo apt-get update` 与 `sudo apt-get install -y --no-upgrade <packages>`；只有这两个子命令使用 `sudo`。没有可用终端时改用 `sudo -n`，需要凭据时会失败并提示在原生终端重试。
- macOS：缺少 Homebrew 时先预览，再用官方安装脚本引导 Homebrew；这一步需要原生终端，而且 Homebrew 自身可能要求管理员凭据或 Apple Command Line Tools。Plasticine 不会用 `sudo bash` 执行它。
- `--yes` 只跳过 Plasticine 自己的最终确认，不会代替 Homebrew、`sudo` 或 `chsh` 的原生提示；无法提供凭据时安装以错误结束，而不是伪造输入。
- 预览先列出所选路径、网络访问、包管理器改动、可能的提权以及将要执行的 `chsh` 命令，然后才请求确认。取消确认只会跳过 apply：已克隆的 chezmoi source 和已记录的工具选择会保留，但不会写入 `~/.zshrc`、`~/.zsh_plugins.txt`、`~/.p10k.zsh` 或 `~/.plasticine`，也不会调用任何安装命令或 `chsh`。
- 上游安装脚本的行为部分不透明；失败时直接报错，不会自动改用其他路径。

### 登录 shell（`chsh`）

- 登录 shell 从原生账户数据库读取（不是 `$SHELL`）；Debian/Ubuntu 上 `/bin/zsh` 与 `/usr/bin/zsh` 视为同一个 Zsh。
- 只有在工具和配置都可用之后才尝试 `chsh -s <zsh 绝对路径>`，并且需要原生终端；不会使用 `sudo chsh`，也不会修改 `/etc/shells`。
- `chsh` 失败（密码错误、账户策略、没有终端等）会保留已经可用的工具与配置，本次安装返回失败；在原生终端里重新运行安装命令即可只重试这一步。
- 登录 shell 已经正确时不会调用 `chsh`，此时 `$SHELL` 的值不影响判断。

### 与旧仓库的关系

- `--shell` 不读取也不执行 `~/.plasticine-dotfiles` 中的任何文件。
- 本功能不删除 `~/.plasticine-dotfiles`，也不迁移或清理任何旧运行时状态（生成的 `.zsh_plugins.zsh`、Antidote 插件克隆、缓存、快照、补全 dump、编译文件、`~/.zsh_plugins.local.txt` 等）。清理旧仓库需要单独的、显式的迁移设计。
- 不选择 `shell` 时不会探测 Zsh 或 Antidote，也不会改动任何 shell 相关状态。

## 本地验证

测试全部运行在临时目录，不会修改真实的 `~/.ssh`、`~/.zshrc` 或 `~/.plasticine`，也不会真的调用包管理器、`sudo`、`brew` 或 `chsh`：

```sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/integration.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/chezmoi.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/installer.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/shell.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/lazygit.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/lazygit-runtime.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/fnm.sh
./tests/fnm-runtime.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/neovim.sh
PLASTICINE_LIVE_NEOVIM_SMOKE=1 ./tests/neovim-runtime.sh
./tests/shell-runtime.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/release.sh
```

`tests/shell.sh` 覆盖安装器侧的 Zsh 选择、工具准备、登录 shell 切换与运行时状态隔离；`tests/lazygit.sh` 用受控 release、网络、平台和文件系统 fixture 覆盖 Lazygit 路线且不会访问真实网络；`tests/fnm.sh` 覆盖 Linux 官方脚本候选发布和 macOS Homebrew currency 路线；`tests/lazygit-runtime.sh` 与 `tests/shell-runtime.sh` 使用真实 Zsh，后者包含受控 fnm 的成功/失败激活、Owner 后续代码继续执行和单次初始化验证。`tests/neovim.sh` 使用受控 Release 与编辑器边界覆盖公开 chezmoi 入口；`tests/neovim-runtime.sh` 是单独标识、显式 opt-in 的 current-upstream smoke，会在一次性 HOME 中用真实 Neovim 和当前插件验证启动、快捷键、文件树与终端。routine 测试不依赖 live Release；Zsh runtime 套件需要本机存在 `zsh`。

## 发布

本仓库使用独立的 SemVer 版本线，从 `v0.1.0` 开始。日常提交和 Pull Request 会在 Ubuntu 与 macOS 上执行完整测试；稳定版本只能从 GitHub Actions 的 `Release` workflow 手动触发，并输入 `vMAJOR.MINOR.PATCH` 格式的版本号。

发布流程验证触发时的 `main` commit，生成 `install.sh` 和 `SHA256SUMS`，先创建 draft Release，核对 tag、commit 与附件后再发布。发布版安装器固定到该 Release 的完整 commit；因此历史 Release 的安装内容不会随 `main` 推进而改变，而 `/releases/latest/download/install.sh` 始终选择最新稳定版本。

发布前应在仓库设置中将 `CI / Test (ubuntu-24.04)` 和 `CI / Test (macos-14)` 配置为 `main` 的 required checks，并启用 GitHub immutable releases。CI 和 Release workflow 中使用的第三方 Actions 固定到完整 commit，由 Dependabot 每月提出更新。
