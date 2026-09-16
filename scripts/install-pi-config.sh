#!/usr/bin/env bash
set -euo pipefail

# Reproduce the portable core of this Pi agent setup: the shared packages, the
# pi-fff extension, and the Fireworks provider defaults. Machine-specific pieces
# (Nix-store links, Databricks skills, the OpenCode Go model catalog) are left
# out on purpose - bring your own FIREWORKS_API_KEY.

agent_dir=${PI_AGENT_DIR:-$HOME/.pi/agent}
settings="$agent_dir/settings.json"
provider=${PI_DEFAULT_PROVIDER:-fireworks}
model=${PI_DEFAULT_MODEL:-accounts/fireworks/models/kimi-k3}
enabled_glob=${PI_ENABLED_MODELS:-fireworks/accounts/fireworks/models/*}

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
