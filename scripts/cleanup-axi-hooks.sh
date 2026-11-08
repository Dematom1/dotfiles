#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
remover="${AXI_HOOK_REMOVER:-$repo_dir/scripts/remove-axi-session-start-hook.py}"
state="$HOME/.local/state/dotfiles/axi-hooks-cleanup-v2"
mkdir -p "$state"
failed=0
tools=(gh-axi chrome-devtools-axi tasks-axi k8s-axi npm-axi pypi-axi homebrew-axi jev-axi bun-axi hetzner-axi argocd-axi argo-workflows-axi datadog-axi)
profile=personal
if [[ -f "$HOME/.config/dotfiles-profile" ]]; then profile="$(<"$HOME/.config/dotfiles-profile")"; fi
if [[ "$profile" == work ]]; then tools+=(slack-axi aws-axi gws-axi notion-axi); fi
for tool in "${tools[@]}"; do
  marker="$state/$tool"
  [[ -e "$marker" || -e "$state/$tool.attempted" ]] && continue
  case "$tool" in
    bun-axi|k8s-axi)
      if ! python3 "$remover" "$HOME" "$tool"; then
        echo "    - $tool hook removal failed; retry next rebuild" >&2
        failed=1
        continue
      fi
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "    - $tool unavailable; retry next rebuild" >&2
        failed=1
        continue
      fi
      if ! touch "$state/$tool.attempted"; then
        echo "    - $tool attempt marker failed; skipping uninstall" >&2
        failed=1
        continue
      fi
      if [[ "$tool" == k8s-axi ]]; then
        if ! "$tool" setup uninstall; then
          echo "    - $tool cleanup failed; not retrying uncertain uninstall" >&2
          failed=1
          continue
        fi
      elif ! "$tool" setup hooks --uninstall; then
        echo "    - $tool cleanup failed; not retrying uncertain uninstall" >&2
        failed=1
        continue
      fi
      ;;
    hetzner-axi|argo-workflows-axi)
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "    - $tool unavailable; retry next rebuild" >&2
        failed=1
        continue
      fi
      if ! touch "$state/$tool.attempted"; then
        echo "    - $tool attempt marker failed; skipping uninstall" >&2
        failed=1
        continue
      fi
      if ! "$tool" setup uninstall; then
        echo "    - $tool cleanup failed; not retrying uncertain uninstall" >&2
        failed=1
        continue
      fi
      ;;
    *)
      if python3 "$remover" "$HOME" "$tool"; then
        :
      else
        status=$?
        if [[ "$tool" == tasks-axi && "$status" -eq 3 ]]; then
          echo "    - $tool has unconfirmed user hooks; leaving it for review" >&2
        else
          echo "    - $tool cleanup failed; retry next rebuild" >&2
        fi
        failed=1
        continue
      fi
      ;;
  esac
  if ! touch "$marker"; then
    echo "    - $tool marker failed; retry next rebuild" >&2
    failed=1
  fi
done
exit "$failed"
