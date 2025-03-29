#!/bin/bash

set -e

echo "🚀 Setting up dotfiles and LazyVim..."

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------
# Terminal dotfiles
# ------------------------------
echo "🔗 Linking terminal dotfiles..."

# ------------------------------
# Neovim config with LazyVim
# ------------------------------
echo "🔗 Linking Neovim config..."
mkdir -p ~/.config
ln -sf "$DOTFILES_DIR/config/nvim" ~/.config/nvim

# ------------------------------
# Lazy.nvim bootstrap (in case it's missing)
# ------------------------------
LAZY_DIR="$HOME/.local/share/nvim/lazy/lazy.nvim"
if [ ! -d "$LAZY_DIR" ]; then
  echo "📥 Installing lazy.nvim..."
  git clone https://github.com/folke/lazy.nvim.git "$LAZY_DIR"
fi

# ------------------------------
# Plugin sync
# ------------------------------
echo "⚙️ Syncing Neovim plugins..."
nvim --headless "+Lazy! sync" +qa

echo "✅ Done! You can now launch Neovim."
