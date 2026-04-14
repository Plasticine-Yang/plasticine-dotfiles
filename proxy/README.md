# Usage

proxy-utils 是本机代理
proxy-utils-wsl2 是让 wsl2 使用宿主机的代理

```shell
sudo ln -s ~/.plasticine-dotfiles/proxy/proxy-utils.sh /usr/local/bin/proxy-utils
```

编辑 `~/.profile`，加上如下内容：

```shell
source proxy-utils setSystemProxy
```
