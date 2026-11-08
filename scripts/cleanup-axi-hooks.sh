#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
remover="${AXI_HOOK_REMOVER:-$repo_dir/scripts/remove-axi-session-start-hook.py}"
state="$HOME/.local/state/dotfiles/axi-hooks-cleanup-v2"
mkdir -p "$state"
backup="$state/snapshot"
if [[ ! -f "$backup/.complete" ]]; then
  rm -rf "$backup"
  snapshot_tmp="$(mktemp -d "$state/.snapshot.XXXXXX")"
  for file in .claude/settings.json .claude/settings.local.json .codex/hooks.json; do
    source="$HOME/$file"
    [[ -f "$source" ]] || continue
    mkdir -p "$snapshot_tmp/$(dirname "$file")"
    if ! cp -pP "$source" "$snapshot_tmp/$file"; then
      rm -rf "$snapshot_tmp"
      echo "    - could not snapshot $source; deferring AXI hook cleanup" >&2
      exit 1
    fi
  done
  touch "$snapshot_tmp/.complete"
  mv "$snapshot_tmp" "$backup"
fi
failed=0
tools=(gh-axi chrome-devtools-axi tasks-axi k8s-axi npm-axi pypi-axi homebrew-axi jev-axi bun-axi hetzner-axi argocd-axi argo-workflows-axi datadog-axi)
profile=personal
if [[ -f "$HOME/.config/dotfiles-profile" ]]; then profile="$(<"$HOME/.config/dotfiles-profile")"; fi
if [[ "$profile" == work ]]; then tools+=(slack-axi aws-axi gws-axi notion-axi); fi
for tool in "${tools[@]}"; do
  marker="$state/$tool"
  [[ -e "$marker" ]] && continue
  case "$tool" in
    bun-axi|k8s-axi)
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "    - $tool unavailable; retry next rebuild" >&2
        failed=1
        continue
      fi
      if ! "$tool" setup hooks --uninstall; then
        echo "    - $tool cleanup failed; retry next rebuild" >&2
        failed=1
        continue
      fi
      ;;
    hetzner-axi|argocd-axi|argo-workflows-axi|datadog-axi)
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "    - $tool unavailable; retry next rebuild" >&2
        failed=1
        continue
      fi
      if ! "$tool" setup uninstall; then
        echo "    - $tool cleanup failed; retry next rebuild" >&2
        failed=1
        continue
      fi
      ;;
    *)
      if ! python3 "$remover" "$HOME" "$tool"; then
        echo "    - $tool cleanup failed; retry next rebuild" >&2
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
