# plasticine-dotfiles

使用 [chezmoi](https://www.chezmoi.io/) 在 macOS 和 Linux 上选择并恢复个人开发环境。目前支持 GitHub SSH 配置。

## 一行安装

在交互终端中运行：

```console
sh -c "$(curl -fsSL https://github.com/Plasticine-Yang/plasticine-dotfiles/releases/latest/download/install.sh)"
```

安装器支持 macOS 和 Linux，会在需要时将已验证的 chezmoi 版本安装到 `~/.local/bin/chezmoi`，然后使用 chezmoi 的默认 source、config 和 state 路径。

安装过程会选择工具、收集所需参数、自动显示变更，并在确认后应用。当前支持 GitHub SSH。

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

已有不同的 `~/.ssh/id_github` 时，自动化调用还需要显式传入 `--replace-github-ssh-key`。可通过 `--github-ssh-test` 在应用后测试连接。`-y` 不会启用 chezmoi 的强制覆盖，配置冲突仍会停止安装。

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

## 本地验证

测试全部运行在临时目录，不会修改真实的 `~/.ssh`：

```sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/integration.sh
CHEZMOI_BIN=/path/to/chezmoi ./tests/installer.sh
```
