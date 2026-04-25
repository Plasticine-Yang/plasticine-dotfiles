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
        
        if [ "$(basename $SHELL)" != "zsh" ]; then
            log_info "当前默认 shell 不是 zsh，正在设置为默认 shell..."
            chsh -s $(which zsh)
            log_success "已将默认 shell 设置为 zsh！请重新登录或重启终端以应用更改。"
        else
            log_info "默认 shell 已经是 zsh。"
        fi
        
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

setup_env() {
    log_info "配置环境变量..."
    ENV_FILE="$HOME/.env"
    ENV_TEMPLATE="$DOTFILES_DIR/.env"
    
    if [ ! -f "$ENV_TEMPLATE" ]; then
        log_warn "未找到 $ENV_TEMPLATE，跳过..."
        return
    fi
    
    if [ -f "$ENV_FILE" ]; then
        log_info "~/.env 已存在，跳过创建。"
        return
    fi
    
    cp "$ENV_TEMPLATE" "$ENV_FILE"
    log_success "环境变量文件 ~/.env 创建完成！"
    
    if [ -f ~/.zshrc ]; then
        if ! grep -q "\.env" ~/.zshrc 2>/dev/null; then
            echo -e "\n# load env\n[ -f ~/.env ] && source ~/.env" >> ~/.zshrc
            log_success "已向 ~/.zshrc 添加环境变量加载配置！"
        else
            log_info "~/.zshrc 已包含 ~/.env 加载配置，跳过。"
        fi
    fi
}

setup_fnm() {
    log_info "配置 FNM..."
    
    if ! command -v fnm >/dev/null 2>&1; then
        log_info "未检测到 FNM，正在安装..."
        curl -fsSL https://fnm.vercel.app/install | bash
        log_success "FNM 安装完成！"
    else
        log_info "FNM 已经安装，跳过安装。"
    fi
    
    if [ ! -f ~/.zshrc ]; then
        log_warn "未找到 ~/.zshrc，跳过 shell 配置..."
        return
    fi
    
    FNM_INIT='eval "$(fnm env --use-on-cd --shell bash)"'
    
    if ! grep -q "fnm env" ~/.zshrc 2>/dev/null; then
        echo -e "\n# fnm\n$FNM_INIT" >> ~/.zshrc
        log_success "已向 ~/.zshrc 添加 fnm 配置！"
    else
        log_info "~/.zshrc 已包含 fnm 配置，跳过。"
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
    echo "默认行为：自动设置仓库并安装 Zsh, Neovim, Git, Env"
    echo ""
    echo "按需安装选项:"
    echo "  --zsh       仅安装配置 Zsh"
    echo "  --nvim      仅安装配置 Neovim"
    echo "  --lazygit   仅安装配置 Lazygit"
    echo "  --proxy     仅安装配置 Proxy Utils"
    echo "  --git       仅安装配置 Git 软链接"
    echo "  --env       仅配置环境变量"
    echo "  --fnm       仅安装配置 FNM"
    echo "  --clash     仅安装配置 Clash"
    echo "  --all       安装所有可用组件"
    echo "  --help, -h  显示此帮助信息"
    echo ""
    echo "示例：./install.sh --git --env"
}

# 解析命令行参数
if [ $# -eq 0 ]; then
    # 默认行为
    setup_dotfiles
    setup_zsh
    setup_nvim
    setup_git
    setup_env
    log_success "默认配置安装结束！请根据需要重启终端或输入 'zsh' 应用最新配置。"
    exit 0
fi

# 按需行为：先检查是否为 help 参数
case $1 in
    -h|--help) show_help; exit 0 ;;
esac

setup_dotfiles

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --zsh) setup_zsh ;;
        --nvim) setup_nvim ;;
        --lazygit) setup_lazygit ;;
        --proxy) setup_proxy ;;
        --git) setup_git ;;
        --env) setup_env ;;
        --fnm) setup_fnm ;;
        --clash) setup_clash ;;
        --all)
            setup_zsh
            setup_nvim
            setup_lazygit
            setup_proxy
            setup_git
            setup_env
            setup_fnm
            setup_clash
            ;;
        -h|--help) show_help; exit 0 ;;
        *) log_error "未知参数：$1"; show_help; exit 1 ;;
    esac
    shift
done

log_success "按需安装流程结束！"
