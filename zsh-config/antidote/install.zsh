# clone antidote if not installed
if [[ ! -d "${ZDOTDIR:-~}/.antidote" ]]; then
  echo "clonling antidote repository..."
  git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
else
  echo "antidote repository already cloned, skip clone."
fi

source ${ZDOTDIR:-~}/.antidote/antidote.zsh

# link .zshrc
cp ~/.plasticine-linux-config/zsh-config/antidote/.zshrc ~/.zshrc

# link .zsh_plugins.txt
cp ~/.plasticine-linux-config/zsh-config/antidote/.zsh_plugins.txt ~/.zsh_plugins.txt

# link .p10k.zsh
cp ~/.plasticine-linux-config/zsh-config/antidote/.p10k.zsh ~/.p10k.zsh

# install fnm
curl -fsSL https://fnm.vercel.app/install | bash

source ~/.zshrc