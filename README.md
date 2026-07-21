# Dotfiles

My macOS development environment, managed with **nix-darwin + home-manager**
(Determinate Nix) plus a `just`-driven agent-tooling layer.

## What's Included

| Tool | Purpose |
|------|---------|
| **nvim** | Neovim config with LSP, DAP, Treesitter |
| **tmux** | Terminal multiplexer |
| **zsh** | Shell (Powerlevel10k; declared in `home.nix` + `zsh/init.zsh`) |
| **ghostty** / **wezterm** | Terminal emulators |
| **atuin** | Shell history search |
| **direnv** | Per-project environments |
| **git** | Git config with delta |
| **yazi** | Terminal file manager |
| **bat** | Syntax-highlighted cat |
| **aerospace** | macOS window manager |
| **sketchybar** | macOS status bar |

## Installation

Prerequisites: [Determinate Nix](https://determinate.systems/) and Homebrew
(nix-darwin drives Homebrew casks via `brew bundle`, but does not install brew).

```bash
# 1. Clone
git clone https://github.com/Dematom1/dotfiles.git ~/Code/dotfiles
cd ~/Code/dotfiles

# 2. (work Mac only) select the work profile
echo work > ~/.config/dotfiles-profile

# 3. Build system + home - installs tools, symlinks every config
./rebuild.sh

# 4. Secrets + agent tooling
op signin && just bootstrap   # ~/.secrets + FirstMate stack + all skills
```

`home.nix` symlinks configs live from this repo (`mkOutOfStoreSymlink`), so most
edits apply without a rebuild.

## Key Bindings

### Neovim

See [nvim/CHEATSHEET.md](nvim/CHEATSHEET.md). Quick reference:

- `<Space>` - Leader key
- `<leader>ff` - Find files
- `<leader>fs` - Live grep
- `<leader>hc` - Open cheatsheet

### Tmux

- `Ctrl-Space` - Prefix
- `prefix + |` / `prefix + -` - Split vertical / horizontal
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
├── flake.nix            # nix-darwin + home-manager flake
├── configuration.nix    # system-level (macOS defaults, Homebrew casks/brews)
├── home.nix             # user-level (packages, dotfile symlinks, zsh)
├── hosts/               # per-machine deltas (personal.nix, work.nix)
├── rebuild.sh           # darwin-rebuild wrapper (picks the profile)
├── justfile             # bootstrap / update / skills / FirstMate recipes
├── .agents/             # agent-agnostic skills + SKILLS.md
├── nvim/                # Neovim configuration
├── zsh/
│   ├── init.zsh         # live-sourced shell extras (functions, PATH, env)
│   └── p10k.zsh         # Powerlevel10k config
├── ghostty/ atuin/ direnv/ git/ yazi/ bat/
├── aerospace/ sketchybar/ karabiner/
├── .wezterm.lua
├── .tmux.conf
└── README.md
```

## Secrets

Secrets live in `~/.secrets` (never committed), generated from 1Password:

```bash
op signin && just refresh-secrets   # renders zsh/secrets.tpl -> ~/.secrets
```

`~/.secrets` is sourced automatically by the home-manager zsh init. For
project-specific secrets, use `.env` + direnv (`echo dotenv > .envrc`).

## Updating

```bash
cd ~/Code/dotfiles && git pull
./rebuild.sh    # rebuild system + home from the flake
just update     # refresh skills + FirstMate agent stack
```

## Credits

- [Neovim](https://neovim.io/)
- [Tmux](https://github.com/tmux/tmux)
- [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- [Tokyo Night](https://github.com/folke/tokyonight.nvim)
- [nix-darwin](https://github.com/nix-darwin/nix-darwin)
- [home-manager](https://github.com/nix-community/home-manager)
