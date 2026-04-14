PLASTICINE_LINUX_CONFIG_DIR=~/.plasticine-dotfiles

# init antidote
source "${PLASTICINE_LINUX_CONFIG_DIR}/zsh-config/antidote/init_antidote.zsh"

# setup plugin config
source "${PLASTICINE_LINUX_CONFIG_DIR}/zsh-config/antidote/plugin-configs/setup.zsh"

# setup user custom bootstrap shell
source "${PLASTICINE_LINUX_CONFIG_DIR}/zsh-config/antidote/setup_user_custom_bootstrap_shell.zsh"

# setup fnm
eval "$(fnm env --use-on-cd --shell zsh)"
