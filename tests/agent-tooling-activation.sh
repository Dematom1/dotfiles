#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
profile=$1
agent_tooling=$(cat "$2")
bash_bin=$(command -v bash)
fail() { echo "FAIL: $*" >&2; exit 1; }

activation_home=$(mktemp -d "$repo/.agent-activation.XXXXXX")
trap 'rm -rf "$activation_home"' EXIT
mkdir -p "$activation_home/Code/dotfiles" "$activation_home/.local/bin" "$activation_home/.pi/agent"
cat > "$activation_home/Code/dotfiles/justfile" <<'EOF'
axi-tools := "review-common-axi"
axi-tools-work := "review-work-axi"
EOF
printf '#!/bin/sh\nexit 1\n' > "$activation_home/.local/bin/claude"
chmod +x "$activation_home/.local/bin/claude"
printf '%s\n' '{"packages":["npm:pi-autoresearch"]}' > "$activation_home/.pi/agent/settings.json"
before=$(cat "$activation_home/.pi/agent/settings.json")
# Activation inherits only a few Nix store tools, never /usr/bin.
plan=$(env -i HOME="$activation_home" PATH= DRY_RUN=1 \
  "$bash_bin" -euo pipefail -c "$agent_tooling" 2>&1)
[[ "$plan" == *"packages -['npm:pi-autoresearch']"* ]] || fail "activation missed Pi removal: $plan"
[[ "$plan" == *"review-common-axi is not installed"* ]] \
  || fail "activation did not use the fixture justfile: $plan"
if [[ "$profile" == work ]]; then
  [[ "$plan" == *"review-work-axi is not installed"* ]] || fail "work activation omitted work tools"
else
  [[ "$plan" != *"review-work-axi"* ]] || fail "non-work activation included work tools"
fi
[[ $(cat "$activation_home/.pi/agent/settings.json") == "$before" ]] || fail "activation dry run mutated Pi"
[[ ! -e "$activation_home/.claude.json" && ! -e "$activation_home/.local/state" ]] \
  || fail "activation dry run created state"
rm -rf "$activation_home"
