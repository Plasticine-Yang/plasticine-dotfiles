# git

## 用户相关

### 全局配置

```shell
git config --global user.email "975036719@qq.com" && \
git config --global user.name "plasticine9750" && \
git config --global credential.helper store
```

### 局部配置

```shell
git config user.email "975036719@qq.com" && \
git config user.name "plasticine9750" && \
git config credential.helper store
```

## 默认分支名

```shell
git config --global init.defaultBranch main
```

## linux 自动配置 ssh 私钥

**将下面脚本中的 `github_pk` 替换成实际的私钥名称**

```shell
# 启动 ssh-agent 并添加 GitHub 密钥
if [ -z "$SSH_AUTH_SOCK" ]; then
  # 检查是否已有 ssh-agent 进程在运行
  if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    ssh-agent -s > "$HOME/.ssh/ssh-agent.env"
  fi
  # 加载 ssh-agent 环境变量
  if [ -f "$HOME/.ssh/ssh-agent.env" ]; then
    . "$HOME/.ssh/ssh-agent.env" > /dev/null
  fi
fi

# 检查密钥是否已添加，未添加则自动添加
if ! ssh-add -l | grep -q "github_pk"; then
  ssh-add ~/.ssh/github_pk 2>/dev/null
fi
```

## 问题

### 1. gnutls_handshake() failed

git clone 的时候遇到下面的报错

```text
gnutls_handshake() failed: The TLS connection was non-properly terminated.
```

运行 `proxy-utils` 脚本中的 `setGITProxy` 即可

```shell
proxy-utils setGITProxy
```
