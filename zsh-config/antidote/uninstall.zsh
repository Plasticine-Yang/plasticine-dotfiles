# remove antidote repository
rm -rf ${ZDOTDIR:-~}/.antidote

# unlink .zshrc
rm -rf ~/.zshrc

# unlink .zsh_plugins.txt
rm -rf ~/.zsh_plugins.txt

# unlink .p10k.zsh
rm -rf ~/.p10k.zsh

# remove plugin files
rm -rf ~/.zcompdump ~/.zsh_history ~/.zsh_plugins.zsh