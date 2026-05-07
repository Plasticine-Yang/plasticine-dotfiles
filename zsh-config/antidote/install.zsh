# clone antidote if not installed
if [[ ! -d "${ZDOTDIR:-$HOME}/.antidote" ]]; then
  echo "clonling antidote repository..."
  git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-$HOME}/.antidote
else
  echo "antidote repository already cloned, skip clone."
fi

source ${ZDOTDIR:-$HOME}/.antidote/antidote.zsh

# link .zshrc
cp ~/.plasticine-dotfiles/zsh-config/antidote/.zshrc ~/.zshrc

# link .zsh_plugins.txt
cp ~/.plasticine-dotfiles/zsh-config/antidote/.zsh_plugins.txt ~/.zsh_plugins.txt

# link .p10k.zsh
cp ~/.plasticine-dotfiles/zsh-config/antidote/.p10k.zsh ~/.p10k.zsh

source ~/.zshrc