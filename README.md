# Dotfiles

My development environment configuration.

## What's Included

| Tool | Purpose |
|------|---------|
| **nvim** | Neovim config with LSP, DAP, Treesitter |
| **tmux** | Terminal multiplexer |
| **zsh** | Shell configuration |
| **ghostty** | Terminal emulator |
| **wezterm** | Terminal emulator (backup) |
| **atuin** | Shell history search |
| **direnv** | Per-project environments |
| **git** | Git config with delta |
| **yazi** | Terminal file manager |
| **bat** | Syntax-highlighted cat |
| **aerospace** | macOS window manager |
| **sketchybar** | macOS status bar |

## Installation

### Prerequisites

```bash
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install all tools from Brewfile
brew bundle install

# Or install uv separately (not in Brewfile - uses installer)
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Setup

```bash
# Clone dotfiles
git clone https://github.com/yourusername/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles

# Run install script
./install.sh

# Or clean install (removes existing configs first)
./install.sh --clean
```

### Manual Setup

If you prefer manual setup:

```bash
# Symlink configs
ln -sf ~/Code/dotfiles/nvim ~/.config/nvim
ln -sf ~/Code/dotfiles/ghostty ~/.config/ghostty
ln -sf ~/Code/dotfiles/.tmux.conf ~/.tmux.conf
ln -sf ~/Code/dotfiles/.wezterm.lua ~/.wezterm.lua
ln -sf ~/Code/dotfiles/atuin/config.toml ~/.config/atuin/config.toml
ln -sf ~/Code/dotfiles/direnv/direnvrc ~/.direnvrc
ln -sf ~/Code/dotfiles/direnv/direnv.toml ~/.config/direnv/direnv.toml
ln -sf ~/Code/dotfiles/yazi ~/.config/yazi
ln -sf ~/Code/dotfiles/bat ~/.config/bat

# Git config (adds include)
git config --global include.path "~/Code/dotfiles/git/config"

# Zsh (source from dotfiles)
echo 'source ~/Code/dotfiles/zsh/zshrc' > ~/.zshrc

# Create secrets file (never committed)
touch ~/.secrets
chmod 600 ~/.secrets
```

## Key Bindings

### Neovim

See [nvim/CHEATSHEET.md](nvim/CHEATSHEET.md) for full keybindings.

Quick reference:
- `<Space>` - Leader key
- `<leader>ff` - Find files
- `<leader>fs` - Live grep
- `<leader>hc` - Open cheatsheet

### Tmux

- `Ctrl-Space` - Prefix
- `prefix + |` - Split vertical
- `prefix + -` - Split horizontal
- `prefix + r` - Reload config
- `Alt+1-5` - Switch windows
- `prefix + C-j` - Session switcher

### Shell

- `Ctrl-R` - Atuin history search
- `Ctrl-T` - FZF repo selector + tmux
- `z <dir>` - Zoxide smart cd
- `y` - Yazi file manager

## Directory Structure

```
dotfiles/
├── nvim/              # Neovim configuration
│   ├── lua/
│   └── CHEATSHEET.md
├── zsh/
│   └── zshrc          # Main shell config
├── ghostty/
│   └── config
├── atuin/
│   └── config.toml
├── direnv/
│   ├── direnvrc       # Helper functions (use_uv, dotenv)
│   ├── direnv.toml
│   └── example.envrc
├── git/
│   └── config         # Delta diff viewer
├── yazi/
├── bat/
├── aerospace/
├── sketchybar/
├── .wezterm.lua
├── .tmux.conf
├── Brewfile           # Homebrew packages
├── install.sh
└── README.md
```

## Secrets

Secrets are stored in `~/.secrets` (never committed):

```bash
# ~/.secrets
export API_KEY="..."
export DATABASE_URL="..."
```

This file is sourced by zshrc automatically.

For project-specific secrets, use `.env` files with direnv:

```bash
# In project directory
echo 'dotenv' > .envrc
echo 'DATABASE_URL=...' > .env
direnv allow
```

## Updating

```bash
cd ~/Code/dotfiles
git pull

# Homebrew packages
brew bundle install
brew upgrade

# Neovim plugins
nvim --headless "+Lazy sync" +qa

# Tmux plugins
~/.tmux/plugins/tpm/bin/update_plugins all
```

## Credits

- [Neovim](https://neovim.io/)
- [Tmux](https://github.com/tmux/tmux)
- [Oh My Zsh](https://ohmyz.sh/)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Tokyo Night](https://github.com/folke/tokyonight.nvim)
