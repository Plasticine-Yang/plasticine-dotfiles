# plasticine-dotfiles

使用 [chezmoi](https://www.chezmoi.io/) 在 macOS 和 Linux 上选择并恢复个人开发环境。目前支持 GitHub SSH 配置、Lazygit 和 Zsh 环境。

## 一行安装

在交互终端中运行：

```console
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)"
```

安装器支持 macOS 和 Linux，会在需要时将已验证的 chezmoi 版本安装到 `~/.local/bin/chezmoi`，然后使用 chezmoi 的默认 source、config 和 state 路径。

安装过程会选择工具、收集所需参数、自动显示变更，并在确认后应用。当前支持 GitHub SSH、Lazygit（`lazygit`）和 Zsh 环境（`shell`）；初始选择为空，不选择某个工具表示本次不处理它。

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

已有的 `lazygit` 只要通过 `lazygit --version` 健康检查，就保留当前版本和安装归属，不升级、不替换。缺失时，Plasticine 在 apply 阶段从 `jesseduffield/lazygit` 的最新 GitHub Release 下载当前 macOS/Linux、`x86_64`/`arm64` 对应的归档及同一 Release 的 `checksums.txt`，验证 SHA-256 后只提取 `lazygit`，以 `0755` 原子发布到 `~/.local/bin/lazygit`。该校验和与归档处于同一 GitHub Release 信任边界，不是独立签名。此路线不调用 Homebrew、APT、`sudo`、`go install` 或第三方安装器，也不需要凭据或终端提示。

下载、Release 元数据、校验、解压、发布或安装后健康检查失败时不会改用其他安装路线，也不会应用别名。已经成功发布的健康工具会保留；修复网络、上游资源或本机文件系统问题后重跑同一命令即可从观测到的健康状态继续。

`--lazygit` 只在 Owner 控制的 `~/.zshrc` 中维护以下区块，并与 `shell` 区块共用同一个组合与备份流程：

```zsh
# >>> Plasticine lazygit >>>
alias lg='lazygit'
# <<< Plasticine lazygit <<<
```

缺失区块按固定工具顺序插到文件开头，已有合法区块原地更新；区块外字节和原文件权限保持不变。一次 apply 即使多个区块同时变化，也只在 `~/.plasticine/backups/integration-blocks/` 生成一个权限为 `0600` 的 `.zshrc` 全量备份；满足状态的重跑不会改写或新增备份。所有选中区块在任何工具安装前验证，所有选中工具健康后才允许备份和配置应用。

Lazygit 的配置、缓存、日志、仓库状态和 `~/.config/lazygit` 都不归 Plasticine 管理，也不会被检查、导入、备份或删除；旧 `~/.plasticine-dotfiles` 及其运行时状态同样不会清理。安装路线不修改 `PATH`：只选 Lazygit 的 Owner 需要自行确保 `~/.local/bin` 已在 `PATH` 中；同时选择 `shell` 时，共享 Zsh 配置会提供现有的 `~/.local/bin` 默认值。

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

被替换的已有文件会先备份到 `~/.plasticine/backups/shell/`（权限 `600`，目录 `700`），并保留原有文件权限。已经满足的安装重复运行不会产生新的写入或备份。

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
CHEZMOI_BIN=/path/to/chezmoi ./tests/installer.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/shell.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/lazygit.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/lazygit-runtime.sh
./tests/shell-runtime.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/release.sh
```

`tests/shell.sh` 覆盖安装器侧的 Zsh 选择、工具准备、登录 shell 切换与运行时状态隔离；`tests/lazygit.sh` 用受控 release、网络、平台和文件系统 fixture 覆盖 Lazygit 路线且不会访问真实网络；`tests/lazygit-runtime.sh` 用真实 Zsh 证明 `lg` 的调用、Owner 后置覆盖、组合顺序和收敛；`tests/shell-runtime.sh` 用真实 Zsh 在临时 HOME 中启动交互式和非交互式 shell，验证受管片段的运行时行为。两个 runtime 套件都需要本机存在 `zsh`。

## 发布

本仓库使用独立的 SemVer 版本线，从 `v0.1.0` 开始。日常提交和 Pull Request 会在 Ubuntu 与 macOS 上执行完整测试；稳定版本只能从 GitHub Actions 的 `Release` workflow 手动触发，并输入 `vMAJOR.MINOR.PATCH` 格式的版本号。

发布流程验证触发时的 `main` commit，生成 `install.sh` 和 `SHA256SUMS`，先创建 draft Release，核对 tag、commit 与附件后再发布。发布版安装器固定到该 Release 的完整 commit；因此历史 Release 的安装内容不会随 `main` 推进而改变，而 `/releases/latest/download/install.sh` 始终选择最新稳定版本。

发布前应在仓库设置中将 `CI / Test (ubuntu-24.04)` 和 `CI / Test (macos-14)` 配置为 `main` 的 required checks，并启用 GitHub immutable releases。CI 和 Release workflow 中使用的第三方 Actions 固定到完整 commit，由 Dependabot 每月提出更新。
