# 检查并加载自定义 bootstrap 文件
CUSTOM_BOOTSTRAP="$HOME/.custom_bootstrap.zsh"
if [ -f "$CUSTOM_BOOTSTRAP" ]; then
  # 文件存在则执行 source
  source "$CUSTOM_BOOTSTRAP"
fi