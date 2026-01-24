# =============================================================================
# Brewfile - Core Development Tools
# =============================================================================
# Install: brew bundle install
# Update:  brew bundle dump --force (regenerates from installed)

# -----------------------------------------------------------------------------
# Taps
# -----------------------------------------------------------------------------
tap "dopplerhq/cli"
tap "felixkratz/formulae"
tap "hashicorp/tap"
tap "heroku/brew"
tap "homebrew/services"
tap "jesseduffield/lazydocker"
tap "jesseduffield/lazygit"
tap "koekeishiya/formulae"
tap "nikitabobko/tap"
tap "render-oss/render"
tap "stripe/stripe-cli"

# -----------------------------------------------------------------------------
# Core CLI Tools
# -----------------------------------------------------------------------------
brew "atuin"              # Shell history search
brew "bat"                # Syntax-highlighted cat
brew "btop"               # System monitor
brew "direnv"             # Per-project environments
brew "eza"                # Modern ls
brew "fastfetch"          # System info
brew "fd"                 # Fast file finder
brew "fzf"                # Fuzzy finder
brew "git"                # Version control
brew "git-delta"          # Better git diffs
brew "jq"                 # JSON processor
brew "neovim"             # Editor
brew "ripgrep"            # Fast grep
brew "thefuck"            # Command correction
brew "tlrc"               # Simplified man pages
brew "tmux"               # Terminal multiplexer
brew "yazi"               # File manager
brew "zoxide"             # Smart cd
brew "zsh-autosuggestions"
brew "zsh-syntax-highlighting"
brew "powerlevel10k"      # Zsh theme

# -----------------------------------------------------------------------------
# Git Tools
# -----------------------------------------------------------------------------
brew "gh"                 # GitHub CLI
brew "git-crypt"          # Encrypt files in git
brew "git-filter-repo"    # Rewrite git history
brew "lazygit"            # TUI git client

# -----------------------------------------------------------------------------
# DevOps / Infrastructure
# -----------------------------------------------------------------------------
brew "hcloud"             # Hetzner cloud CLI
brew "helm"               # Kubernetes packages
brew "k9s"                # Kubernetes TUI
brew "kubectx"            # K8s context switcher
brew "minikube"           # Local kubernetes
brew "tailscale"          # VPN
brew "velero"             # K8s backup
brew "dopplerhq/cli/doppler"  # Secrets management
brew "heroku/brew/heroku"     # Heroku CLI
brew "jesseduffield/lazydocker/lazydocker"  # Docker TUI
brew "hashicorp/tap/terraform"  # Infrastructure as code
brew "stripe/stripe-cli/stripe" # Stripe CLI

# -----------------------------------------------------------------------------
# Databases
# -----------------------------------------------------------------------------
brew "duckdb"             # Analytical database
brew "etcd"               # Distributed KV store
brew "mysql", restart_service: :changed
brew "postgresql@14"
brew "redis"

# -----------------------------------------------------------------------------
# Languages / Runtimes
# -----------------------------------------------------------------------------
brew "node@20", link: true
brew "pnpm"               # Node package manager
brew "python@3.11"
brew "python@3.12"
brew "biome"              # JS/TS linter/formatter
brew "luarocks"           # Lua package manager

# -----------------------------------------------------------------------------
# Data Tools
# -----------------------------------------------------------------------------
brew "b2-tools"           # Backblaze B2 CLI
brew "csvkit"             # CSV tools
brew "jqp"                # Interactive jq
brew "qsv"                # Fast CSV toolkit
brew "sevenzip"           # Archive tool
brew "trash"              # Safe delete

# -----------------------------------------------------------------------------
# Build / Dev Dependencies
# -----------------------------------------------------------------------------
brew "prek"               # Fast pre-commit (Rust)
brew "shellcheck"         # Shell script linter
brew "gnupg"              # GPG for git signing

# -----------------------------------------------------------------------------
# macOS Apps
# -----------------------------------------------------------------------------
cask "1password-cli"
cask "nikitabobko/tap/aerospace"  # Tiling window manager
cask "gcloud-cli"                 # Google Cloud
cask "ghostty"                    # Terminal
cask "wezterm"                    # Terminal (backup)
cask "hashicorp/tap/hashicorp-vagrant"
cask "sf-symbols"
cask "xquartz"

# -----------------------------------------------------------------------------
# Fonts
# -----------------------------------------------------------------------------
cask "font-hack-nerd-font"
cask "font-meslo-lg-nerd-font"
cask "font-sf-pro"
cask "font-symbols-only-nerd-font"

# -----------------------------------------------------------------------------
# macOS Status Bar
# -----------------------------------------------------------------------------
brew "felixkratz/formulae/sketchybar"
