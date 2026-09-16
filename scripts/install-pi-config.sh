#!/usr/bin/env bash
set -euo pipefail

# Reproduce the portable core of this Pi agent setup: the shared packages, the
# pi-fff extension, and the Fireworks provider defaults. Machine-specific pieces
# (Nix-store links, Databricks skills, the OpenCode Go model catalog) are left
# out on purpose - bring your own FIREWORKS_API_KEY.
#
# Optional: set INSTALL_FIRSTMATE=1 to also clone the Firstmate supervisor repo
# so you can launch it with `pi`. See https://github.com/kunchenguid/firstmate.

agent_dir=${PI_AGENT_DIR:-$HOME/.pi/agent}
settings="$agent_dir/settings.json"
provider=${PI_DEFAULT_PROVIDER:-fireworks}
model=${PI_DEFAULT_MODEL:-accounts/fireworks/models/kimi-k3}
enabled_glob=${PI_ENABLED_MODELS:-fireworks/accounts/fireworks/models/*}

install_firstmate=${INSTALL_FIRSTMATE:-0}
firstmate_repo=${FIRSTMATE_REPO:-https://github.com/kunchenguid/firstmate}
firstmate_dir=${FIRSTMATE_DIR:-$HOME/firstmate}

packages=(
  npm:@nikolauska/linear-axi
  npm:pi-autoresearch
  npm:@ff-labs/pi-fff
)

command -v pi >/dev/null 2>&1 || {
  echo "pi is not on PATH. Install Pi first: https://github.com/earendil-works/pi" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

for pkg in "${packages[@]}"; do
  # Skip pi-fff as a package if it is already provided as a linked extension
  # (e.g. Nix/Home Manager): installing both makes its flags collide on launch.
  if [ "$pkg" = "npm:@ff-labs/pi-fff" ] && [ -e "$agent_dir/extensions/pi-fff" ]; then
    echo "skipping $pkg (already linked at $agent_dir/extensions/pi-fff)"
    continue
  fi
  echo "installing $pkg"
  pi install "$pkg"
done

mkdir -p "$agent_dir"
[ -f "$settings" ] || echo '{}' > "$settings"

tmp=$(mktemp "$settings.XXXXXX")
jq \
  --arg provider "$provider" \
  --arg model "$model" \
  --arg enabled "$enabled_glob" \
  '. + {
    defaultProvider: $provider,
    defaultModel: $model,
    enabledModels: [$enabled],
    theme: "dark",
    hideThinkingBlock: true
  }' "$settings" > "$tmp"
mv "$tmp" "$settings"

echo "done. settings written to $settings"
[ -n "${FIREWORKS_API_KEY:-}" ] || echo "note: set FIREWORKS_API_KEY for the $provider provider before launching pi."

case "$install_firstmate" in
  1|true|yes)
    command -v git >/dev/null 2>&1 || { echo "git is required for Firstmate setup." >&2; exit 1; }
    if [ -d "$firstmate_dir/.git" ]; then
      echo "Firstmate already cloned at $firstmate_dir"
    else
      echo "cloning Firstmate into $firstmate_dir"
      git clone "$firstmate_repo" "$firstmate_dir"
    fi
    echo "Firstmate ready. Launch it with: cd $firstmate_dir && pi"
    ;;
esac
