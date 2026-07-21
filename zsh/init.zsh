# =============================================================================
# Zsh extras - live-editable (functions, PATH, tool init, env).
# Structure (prompt, plugins, aliases, history) is declared in home.nix.
# Sourced at the end of the home-manager-generated ~/.zshrc.
# =============================================================================

# --- PATH (volta/cargo set in home.nix envExtra; nix per-user for home.packages) ---
export PATH="/etc/profiles/per-user/$USER/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="/usr/local/zig:$PATH"
export PATH="$HOME/.lmstudio/bin:$PATH"
export PATH="$HOME/.opencode/bin:$PATH"

# --- Tool initialization ---
eval "$(fzf --zsh)"
eval "$(direnv hook zsh)"
eval "$(zoxide init zsh)"
eval "$(atuin init zsh)"

# --- SSH agent (1Password) ---
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock

# --- Completions ---
command -v kubectl >/dev/null && source <(kubectl completion zsh)
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

# --- History extras (size/dedup set declaratively in home.nix) ---
setopt hist_verify
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# --- Sketchybar: expose cwd for git-branch integration ---
function update_sketchybar_pwd() { echo "$PWD" > /tmp/sketchybar_pwd; }
add-zsh-hook chpwd update_sketchybar_pwd
update_sketchybar_pwd

# --- FZF ---
export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="find ~/code -maxdepth 2 -type d -name .git | sed 's|/.git||'"
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"

fg="#CBE0F0"; bg="#011628"; bg_highlight="#143652"
purple="#B388FF"; blue="#06BCE4"; cyan="#2CF9ED"
export FZF_DEFAULT_OPTS="--color=fg:${fg},bg:${bg},hl:${purple},fg+:${fg},bg+:${bg_highlight},hl+:${purple},info:${blue},prompt:${cyan},pointer:${cyan},marker:${cyan},spinner:${cyan},header:${cyan}"

show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi"
export FZF_CTRL_T_OPTS="--preview '$show_file_or_dir_preview'"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -200'"

_fzf_compgen_path() { fd --hidden --exclude .git . "$1"; }
_fzf_compgen_dir()  { fd --type=d --hidden --exclude .git . "$1"; }
_fzf_comprun() {
  local command=$1; shift
  case "$command" in
    cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
    export|unset) fzf --preview "eval 'echo ${}'" "$@" ;;
    ssh)          fzf --preview 'dig {}' "$@" ;;
    *)            fzf --preview "$show_file_or_dir_preview" "$@" ;;
  esac
}

# --- Functions ---

# Yazi file manager (cd to selected dir on exit)
function y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

# FZF repo selector with tmux
repo-tmux() {
  if [[ -n "$TMUX" ]]; then
    echo "Already in tmux. Use C-Space then C-j to switch sessions."
    return
  fi
  local repo=$(find ~/code -maxdepth 2 -type d -name .git | sed 's|/.git||' | \
    fzf --height 40% --reverse --border --info=inline \
        --preview 'ls -la {}' --preview-window=right:50%:hidden \
        --bind 'ctrl-/:toggle-preview' --prompt="📁 Repo: ")
  if [[ -n "$repo" ]]; then
    local session_name=$(basename "$repo")
    if ! tmux has-session -t "$session_name" 2>/dev/null; then
      tmux new-session -d -s "$session_name" -c "$repo"
    fi
    BUFFER="tmux attach-session -t ${(q)session_name}"
    zle accept-line
  else
    zle reset-prompt
  fi
}
zle -N repo-tmux
bindkey '^t' repo-tmux

# Deploy: tag & push for GitHub Actions (env = prod|staging|dev, optional /image)
deploy() {
  local arg="${1:-prod}"
  local env image
  if [[ "$arg" == */* ]]; then
    env=$(echo "$arg" | cut -d/ -f1)
    image=$(echo "$arg" | cut -d/ -f2)
  else
    env="$arg"; image=""
  fi
  if [[ ! "$env" =~ ^(prod|staging|dev)$ ]]; then
    echo "❌ Invalid environment. Use: prod, staging, or dev"; return 1
  fi
  local app_name=$(git remote get-url origin | sed -E 's|.*/([^/]+)\.git$|\1|; s|.*/([^/]+)$|\1|')
  if [[ -z "$app_name" ]]; then echo "❌ Could not detect app name from git remote"; return 1; fi
  if ! git rev-parse --git-dir > /dev/null 2>&1; then echo "❌ Not in a git repository"; return 1; fi
  if [[ -n $(git status --porcelain) ]]; then
    echo "❌ Working directory not clean. Commit or stash changes first."; return 1
  fi
  if [[ -n "$image" && ! -d "images/$image" ]]; then
    echo "❌ Image '$image' not found in images/ directory"; return 1
  fi
  local sha=$(git rev-parse --short HEAD)
  local tag
  if [[ -n "$image" ]]; then tag="${env}/${image}/${sha}"; else tag="${env}/${sha}"; fi
  echo "🚀 Deploying ${app_name} to ${env}..."
  [[ -n "$image" ]] && echo "   Image: $image" || echo "   All images"
  echo "   Tag: $tag"; echo ""
  if ! git tag "$tag" 2>/dev/null; then
    echo "❌ Tag $tag already exists"; return 1
  fi
  if git push origin "$tag"; then
    echo "✅ Tag pushed! GitHub Actions will build & push."
    echo "   🔗 Watch: https://github.com/${GITHUB_ORG}/${app_name}/actions"
  else
    echo "❌ Push failed; removing local tag $tag"; git tag -d "$tag" >/dev/null; return 1
  fi
}
alias deploy-prod='deploy prod'
alias deploy-staging='deploy staging'
alias deploy-dev='deploy dev'

# --- Misc env ---
export BAT_THEME=tokyonight_night
export HEADROOM_OUTPUT_SHAPER=1
export MEMTRACE_MEMDB_ENDPOINT=http://127.0.0.1:50151
export MEMTRACE_MEMDB_LOOPBACK_PORT=50151
export MEMTRACE_UI_PORT=3131
