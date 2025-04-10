#!/bin/bash

set -e

echo "🚀 Setting up dotfiles and LazyVim..."

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------
# Terminal dotfiles
# ------------------------------
echo "🔗 Linking ~/.config entries from $DOTFILES_DIR..."
mkdir -p ~/.config

for dir in "$DOTFILES_DIR"/*; do
  name=$(basename "$dir")
  target="$HOME/.config/$name"

  # Only link if it's a directory (e.g., nvim/, wezterm/)
  if [ -d "$dir" ]; then
    if [ -L "$target" ]; then
      if $FORCE; then
        echo "♻️ Replacing existing symlink: $target"
        rm "$target"
        ln -s "$dir" "$target"
      else
        echo "⏩ Symlink already exists: $target"
      fi
    elif [ -e "$target" ]; then
      echo "📦 Backing up existing: $target -> $target.bak"
      mv "$target" "$target.bak"
      ln -s "$dir" "$target"
      echo "🔗 Linked: $target → $dir"
    else
      ln -s "$dir" "$target"
      echo "🔗 Linked: $target → $dir"
    fi
  fi
done

# ------------------------------
# Dotfiles (non-dirs) → ~/.*
# ------------------------------
echo "🔗 Linking standalone dotfiles to ~ ..."
for file in "$DOTFILES_DIR"/.*; do
  name=$(basename "$file")

  # Skip .git, .DS_Store, etc.
  [[ "$name" == "." || "$name" == ".." || "$name" == ".git" || "$name" == ".config" ]] && continue

  target="$HOME/$name"

  if [ -L "$target" ]; then
    if $FORCE; then
      echo "♻️ Replacing existing symlink: $target"
      rm "$target"
      ln -s "$file" "$target"
    else
      echo "⏩ Symlink already exists: $target"
    fi
  elif [ -e "$target" ]; then
    echo "📦 Backing up existing: $target -> $target.bak"
    mv "$target" "$target.bak"
    ln -s "$file" "$target"
    echo "🔗 Linked: $target → $file"
  else
    ln -s "$file" "$target"
    echo "🔗 Linked: $target → $file"
  fi
done

# ------------------------------
# Lazy.nvim bootstrap (optional)
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
