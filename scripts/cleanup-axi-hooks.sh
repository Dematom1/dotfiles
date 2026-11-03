#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
state="$HOME/.local/state/dotfiles/axi-hooks-cleanup"
mkdir -p "$state"
tools=(gh-axi chrome-devtools-axi tasks-axi npm-axi pypi-axi homebrew-axi jev-axi bun-axi hetzner-axi argocd-axi argo-workflows-axi datadog-axi slack-axi aws-axi gws-axi notion-axi)
for tool in "${tools[@]}"; do
  marker="$state/$tool"
  [[ -e "$marker" ]] && continue
  case "$tool" in
    bun-axi)
      if ! command -v "$tool" >/dev/null 2>&1; then echo "    - $tool unavailable; retry next rebuild"; continue; fi
      "$tool" setup hooks --uninstall ;;
    hetzner-axi|argocd-axi|argo-workflows-axi|datadog-axi)
      if ! command -v "$tool" >/dev/null 2>&1; then echo "    - $tool unavailable; retry next rebuild"; continue; fi
      "$tool" setup uninstall ;;
    *)
      python3 "$repo_dir/scripts/remove-axi-session-start-hook.py" "$HOME" "$tool" ;;
  esac
  touch "$marker"
done
