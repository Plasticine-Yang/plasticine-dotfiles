## WSL2 注意事项

如果使用 WSL2，默认会将 windows 的 PATH 环境变量挂载到 WSL2 中，导致 zsh 的速度变慢

推荐将这个特性关闭，然后手动将需要用到的 windows 的环境变量添加到 `.profile` 中，比如 vscode 的 code 可执行程序所在路径

创建 `/etc/wsl.conf`

```text
[interop]
appendWindowsPath = false
```

重启即可
