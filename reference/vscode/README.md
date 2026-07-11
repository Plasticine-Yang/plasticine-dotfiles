# vscode

## Usage

安装插件:

安装的插件来自于`extensions.txt`中，如：

```shell
code --install-extension Vue.volar
```

## 插件导出

```shell
# 插件导出
code --list-extensions | sed -e 's/^/code --install-extension /' > my_vscode_extensions.sh

# 插件安装
bash my_vscode_extensions.sh
```
