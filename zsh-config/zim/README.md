# zim

## Install

```shell
curl -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh
```

如果出现网络问题，请加上 `-x` 参数使 curl 通过你的代理去下载脚本

```shell
curl -x socks5h://xxx.xxx.xxx.xxx:xxxx -fsSL https://raw.githubusercontent.com/zimfw/install/master/install.zsh | zsh
```

## Usage

```shell
rm -f ~/.zimrc ~/.zshrc
ln -s ~/.plasticine-linux-config/zsh-config/zim/.zimrc ~/.zimrc
ln -s ~/.plasticine-linux-config/zsh-config/zim/.zshrc ~/.zshrc
ln -s ~/.plasticine-linux-config/zsh-config/zim/.p10k.zsh ~/.p10k.zsh
zimfw install
```

## 重新定制主题

```shell
p10k configure
```
