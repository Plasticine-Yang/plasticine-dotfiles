# lazygit

## Install

### Linux

```shell
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name":' |  sed -E 's/.*"v*([^"]+)".*/\1/')
curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
sudo tar xf lazygit.tar.gz -C /usr/local/bin lazygit
sudo ln -s /usr/local/bin/lazygit /usr/local/bin/lg
rm -f lazygit.tar.gz
```

### Mac

```shell
brew install lazygit
ln -s /opt/homebrew/bin/lazygit /usr/local/bin/lg
```
