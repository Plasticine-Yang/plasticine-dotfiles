# plasticine-dotfiles

my dotfiles

## Usage

```shell
curl -fsSL https://raw.githubusercontent.com/Plasticine-Yang/plasticine-dotfiles/main/install.sh | bash
```

或者手动 clone 后运行：

```shell
git clone https://github.com/Plasticine-Yang/plasticine-dotfiles.git ~/.plasticine-dotfiles
cd ~/.plasticine-dotfiles
./install.sh
```

默认情况下 `install.sh` 只会安装并配置 `Zsh`、`Neovim` 和 `Lazygit`。
你可以通过附加参数按需安装其他组件或覆盖默认行为：

```shell
./install.sh --help
```
