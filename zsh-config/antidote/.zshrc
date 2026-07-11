PLASTICINE_LINUX_CONFIG_DIR=~/.plasticine-dotfiles

# init antidote
source "${PLASTICINE_LINUX_CONFIG_DIR}/zsh-config/antidote/init_antidote.zsh"

# setup plugin config
source "${PLASTICINE_LINUX_CONFIG_DIR}/zsh-config/antidote/plugin-configs/setup.zsh"

# uv env
if [ -f "$HOME/.local/bin/env" ]; then
    source "$HOME/.local/bin/env"
fi
