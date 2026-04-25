#!/usr/bin/env bash

set -e

DOTFILES_DIR="$HOME/.plasticine-dotfiles"

# 颜色输出
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

log_info() {
    echo -e "${BLUE}[INFO]${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${RESET} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${RESET} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${RESET} $1"
}

setup_dotfiles() {
    log_info "设置 dotfiles 仓库..."
    if [ ! -d "$DOTFILES_DIR" ]; then
        log_info "正在克隆 plasticine-dotfiles 仓库..."
        git clone https://github.com/Plasticine-Yang/plasticine-dotfiles.git "$DOTFILES_DIR"
        log_success "克隆完成！"
    else
        log_info "发现已存在的 dotfiles 仓库，正在更新..."
        cd "$DOTFILES_DIR" && git pull
        log_success "更新完成！"
    fi
}

setup_zsh() {
    log_info "配置 Zsh (Antidote)..."
    if [ ! -f "$DOTFILES_DIR/zsh-config/antidote/install.zsh" ]; then
        log_warn "未找到 zsh-config/antidote/install.zsh，跳过..."
        return
    fi
    
    if command -v zsh >/dev/null 2>&1; then
        zsh "$DOTFILES_DIR/zsh-config/antidote/install.zsh"
        log_success "Zsh 配置完成！"
    else
        log_warn "系统中未安装 zsh，请先安装 zsh 后再重新运行或手动配置。"
    fi
}

setup_nvim() {
    log_info "配置 Neovim..."
    
    if ! command -v nvim >/dev/null 2>&1; then
        log_info "未检测到 Neovim，正在下载稳定版..."
        if [ "$(uname)" == "Linux" ]; then
            curl -LO https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
            tar -zxvf nvim-linux-x86_64.tar.gz
            sudo mv ./nvim-linux-x86_64 ~/.nvim
            sudo ln -sf ~/.nvim/bin/nvim /usr/local/bin
            rm -rf ./nvim-linux-x86_64.tar.gz
        elif [ "$(uname)" == "Darwin" ]; then
            log_warn "Mac 系统建议使用 Homebrew 安装 Neovim: brew install neovim"
        fi
        log_success "Neovim 安装完成！"
    else
        log_info "Neovim 已经安装，跳过下载。"
    fi

    mkdir -p ~/.config
    if [ -L "$HOME/.config/nvim" ] || [ -d "$HOME/.config/nvim" ]; then
        log_warn "~/.config/nvim 已经存在，尝试备份为 nvim.bak..."
        mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak"
    fi
    ln -sf "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
    log_success "Neovim 配置链接完成！"
}

setup_lazygit() {
    log_info "配置 Lazygit..."
    
    if ! command -v lazygit >/dev/null 2>&1; then
        if [ "$(uname)" == "Linux" ]; then
            LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name":' |  sed -E 's/.*"v*([^"]+)".*/\1/')
            curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
            sudo tar xf lazygit.tar.gz -C /usr/local/bin lazygit
            sudo ln -sf /usr/local/bin/lazygit /usr/local/bin/lg
            rm -f lazygit.tar.gz
        elif [ "$(uname)" == "Darwin" ]; then
            if command -v brew >/dev/null 2>&1; then
                brew install lazygit
                sudo ln -sf /opt/homebrew/bin/lazygit /usr/local/bin/lg
            else
                log_error "Mac 系统上未找到 Homebrew，请先安装 Homebrew 或手动安装 Lazygit。"
                return
            fi
        fi
        log_success "Lazygit 安装完成！"
    else
        log_info "Lazygit 已经安装，跳过下载。"
    fi
}

setup_proxy() {
    log_info "配置 Proxy Utils..."
    if [ ! -f "$DOTFILES_DIR/proxy/proxy-utils.sh" ]; then
        log_warn "未找到 proxy/proxy-utils.sh，跳过..."
        return
    fi
    
    sudo ln -sf "$DOTFILES_DIR/proxy/proxy-utils.sh" /usr/local/bin/proxy-utils
    
    if ! grep -q "source proxy-utils setSystemProxy" ~/.profile 2>/dev/null; then
        echo -e "\n# proxy-utils\nsource proxy-utils setSystemProxy" >> ~/.profile
        log_success "已向 ~/.profile 添加 proxy-utils 配置！"
    else
        log_info "~/.profile 已包含 proxy-utils 配置，跳过。"
    fi
    log_success "Proxy Utils 配置完成！"
}

setup_git() {
    log_info "配置 Git 软链接..."
    if [ -f "$DOTFILES_DIR/git/.gitconfig" ]; then
        if [ -f ~/.gitconfig ] || [ -L ~/.gitconfig ]; then
            log_warn "~/.gitconfig 已经存在，尝试备份为 .gitconfig.bak..."
            mv ~/.gitconfig ~/.gitconfig.bak
        fi
        ln -sf "$DOTFILES_DIR/git/.gitconfig" ~/.gitconfig
        log_success "Git 配置链接完成！"
    else
        log_warn "未找到 $DOTFILES_DIR/git/.gitconfig，跳过..."
    fi
}

setup_vscode() {
    log_info "配置 VSCode Snippets..."
    if [ "$(uname)" == "Darwin" ]; then
        VSCODE_SNIPPETS_DIR="$HOME/Library/Application Support/Code/User/snippets"
    else
        VSCODE_SNIPPETS_DIR="$HOME/.config/Code/User/snippets"
    fi
    
    if [ -d "$DOTFILES_DIR/vscode/snippets" ]; then
        mkdir -p "$VSCODE_SNIPPETS_DIR"
        # 链接每个 snippet 文件
        for file in "$DOTFILES_DIR"/vscode/snippets/*.json; do
            if [ -f "$file" ]; then
                filename=$(basename "$file")
                ln -sf "$file" "$VSCODE_SNIPPETS_DIR/$filename"
                log_info "已链接 $filename"
            fi
        done
        log_success "VSCode Snippets 配置链接完成！"
    else
        log_warn "未找到 VSCode Snippets 目录，跳过..."
    fi
}

setup_clash() {
    log_info "配置 Clash..."
    if [ -f "$DOTFILES_DIR/clash-installer/clash_installer.sh" ]; then
        cd "$DOTFILES_DIR/clash-installer" && sh ./clash_installer.sh
        log_success "Clash 配置完成！"
    else
        log_warn "未找到 Clash 安装脚本，跳过..."
    fi
}

show_help() {
    echo -e "${BLUE}=======================================${RESET}"
    echo -e "${GREEN}  Plasticine Dotfiles Installer${RESET}"
    echo -e "${BLUE}=======================================${RESET}"
    echo ""
    echo "默认行为: 自动设置仓库并安装 Zsh, Neovim, Lazygit"
    echo ""
    echo "按需安装选项:"
    echo "  --zsh       仅安装配置 Zsh"
    echo "  --nvim      仅安装配置 Neovim"
    echo "  --lazygit   仅安装配置 Lazygit"
    echo "  --proxy     仅安装配置 Proxy Utils"
    echo "  --git       仅安装配置 Git 软链接"
    echo "  --vscode    仅安装配置 VSCode Snippets"
    echo "  --clash     仅安装配置 Clash"
    echo "  --all       安装所有可用组件"
    echo "  --help, -h  显示此帮助信息"
    echo ""
    echo "示例: ./install.sh --git --vscode"
}

# 解析命令行参数
if [ $# -eq 0 ]; then
    # 默认行为
    setup_dotfiles
    setup_zsh
    setup_nvim
    setup_lazygit
    log_success "默认配置安装结束！请根据需要重启终端或输入 'zsh' 应用最新配置。"
    exit 0
fi

# 按需行为
setup_dotfiles

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --zsh) setup_zsh ;;
        --nvim) setup_nvim ;;
        --lazygit) setup_lazygit ;;
        --proxy) setup_proxy ;;
        --git) setup_git ;;
        --vscode) setup_vscode ;;
        --clash) setup_clash ;;
        --all)
            setup_zsh
            setup_nvim
            setup_lazygit
            setup_proxy
            setup_git
            setup_vscode
            setup_clash
            ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "未知参数: $1"; show_help; exit 1 ;;
    esac
    shift
done

log_success "按需安装流程结束！"
