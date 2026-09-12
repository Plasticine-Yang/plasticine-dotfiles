# plasticine-dotfiles

使用 [chezmoi](https://www.chezmoi.io/) 在 macOS 和 Linux 上选择并恢复个人开发环境。目前支持 GitHub SSH 配置。

## 依赖

- chezmoi（已用 2.72.1 验证）
- OpenSSH（`ssh` 和 `ssh-keygen`）

macOS 可以通过 Homebrew 安装 chezmoi：

```sh
brew install chezmoi
```

Linux 请使用发行版包管理器或 chezmoi 官方发布的二进制文件。

## 使用

首次初始化：

```sh
chezmoi init <repo-url>
```

初始化过程中可以多选要处理的工具。选择 `github-ssh` 后，需要输入现有 SSH 私钥的绝对路径或 `~/` 开头的路径。然后先预览，再应用：

```sh
chezmoi diff
chezmoi apply
```

也可以在确认初始化选项后立即应用：

```sh
chezmoi init --apply <repo-url>
```

需要重新选择工具或更换私钥时，再运行：

```sh
chezmoi init
chezmoi diff
chezmoi apply
```

不选择某个工具表示本次不处理它，不会自动卸载工具或删除已有配置。

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
```
