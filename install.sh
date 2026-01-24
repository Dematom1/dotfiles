#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DOTFILES="$HOME/Code/dotfiles"

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
CLEAN=false

usage() {
    echo "Usage: ./install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --clean    Remove existing configs before installing (fresh start)"
    echo "  --help     Show this help message"
    exit 0
}

for arg in "$@"; do
    case $arg in
        --clean)
            CLEAN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
    esac
done

# -----------------------------------------------------------------------------
# Clean mode - remove existing configs
# -----------------------------------------------------------------------------
if [ "$CLEAN" = true ]; then
    echo -e "${YELLOW}🧹 Clean mode: removing existing configs...${NC}"
    echo ""

    # Config directories
    rm -rf "$HOME/.config/nvim"
    rm -rf "$HOME/.config/ghostty"
    rm -rf "$HOME/.config/yazi"
    rm -rf "$HOME/.config/bat"
    rm -rf "$HOME/.config/atuin"
    rm -rf "$HOME/.config/direnv"
    rm -rf "$HOME/.config/aerospace"
    rm -rf "$HOME/.config/sketchybar"

    # Config files
    rm -f "$HOME/.tmux.conf"
    rm -f "$HOME/.wezterm.lua"
    rm -f "$HOME/.direnvrc"
    rm -f "$HOME/.zshrc"

    # Remove backups too
    rm -f "$HOME/.zshrc.backup"
    rm -f "$HOME/.tmux.conf.backup"

    echo -e "${GREEN}  ✓ Cleaned existing configs${NC}"
    echo ""
fi

echo "🔧 Installing dotfiles from $DOTFILES"
echo ""

# Helper function
link() {
    local src="$1"
    local dst="$2"

    # Create parent directory if needed
    mkdir -p "$(dirname "$dst")"

    # Backup existing file if it's not a symlink
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        echo -e "${YELLOW}  Backing up existing $dst${NC}"
        mv "$dst" "$dst.backup"
    fi

    # Remove existing symlink
    [ -L "$dst" ] && rm "$dst"

    # Create symlink
    ln -sf "$src" "$dst"
    echo -e "${GREEN}  ✓ $dst${NC}"
}

# -----------------------------------------------------------------------------
# Config directories (~/.config/*)
# -----------------------------------------------------------------------------
echo "📁 Linking config directories..."

link "$DOTFILES/nvim" "$HOME/.config/nvim"
link "$DOTFILES/ghostty" "$HOME/.config/ghostty"
link "$DOTFILES/yazi" "$HOME/.config/yazi"
link "$DOTFILES/bat" "$HOME/.config/bat"
link "$DOTFILES/aerospace" "$HOME/.config/aerospace"
link "$DOTFILES/sketchybar" "$HOME/.config/sketchybar"

# -----------------------------------------------------------------------------
# Individual config files
# -----------------------------------------------------------------------------
echo ""
echo "📄 Linking config files..."

link "$DOTFILES/.tmux.conf" "$HOME/.tmux.conf"
link "$DOTFILES/.wezterm.lua" "$HOME/.wezterm.lua"
link "$DOTFILES/atuin/config.toml" "$HOME/.config/atuin/config.toml"
link "$DOTFILES/direnv/direnvrc" "$HOME/.direnvrc"
link "$DOTFILES/direnv/direnv.toml" "$HOME/.config/direnv/direnv.toml"

# -----------------------------------------------------------------------------
# Zsh
# -----------------------------------------------------------------------------
echo ""
echo "🐚 Setting up zsh..."

if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    echo -e "${YELLOW}  Backing up existing ~/.zshrc${NC}"
    mv "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

cat > "$HOME/.zshrc" << 'EOF'
# Source main config from dotfiles
source ~/Code/dotfiles/zsh/zshrc

# Machine-specific overrides (optional)
# [[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
EOF
echo -e "${GREEN}  ✓ ~/.zshrc${NC}"

# -----------------------------------------------------------------------------
# Git
# -----------------------------------------------------------------------------
echo ""
echo "🔀 Setting up git..."

git config --global include.path "$DOTFILES/git/config"
echo -e "${GREEN}  ✓ Git include path set${NC}"

# -----------------------------------------------------------------------------
# Secrets file
# -----------------------------------------------------------------------------
echo ""
echo "🔐 Setting up secrets..."

if [ ! -f "$HOME/.secrets" ]; then
    touch "$HOME/.secrets"
    chmod 600 "$HOME/.secrets"
    echo -e "${GREEN}  ✓ Created ~/.secrets${NC}"
    echo -e "${YELLOW}  ⚠ Add your secrets to ~/.secrets${NC}"
else
    echo -e "${GREEN}  ✓ ~/.secrets already exists${NC}"
fi

# -----------------------------------------------------------------------------
# Bat theme cache
# -----------------------------------------------------------------------------
echo ""
echo "🦇 Building bat theme cache..."

if command -v bat &> /dev/null; then
    bat cache --build > /dev/null 2>&1
    echo -e "${GREEN}  ✓ Bat cache built${NC}"
fi

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo -e "${GREEN}✅ Dotfiles installed!${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart your terminal or run: source ~/.zshrc"
echo "  2. In tmux, press prefix + I to install plugins"
echo "  3. In nvim, run :Lazy sync"
echo "  4. Add your secrets to ~/.secrets"
