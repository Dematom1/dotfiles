#!/usr/bin/env bash
set -euo pipefail

if [[ -x "$HOME/.local/bin/claude" ]]; then
  exit 0
fi
if [[ -n ${DRY_RUN:-} ]]; then
  echo "Would install native Claude Code in $HOME/.local/bin"
  exit 0
fi

echo "==> Claude Code (native install; it updates itself)"
if ! curl -fsSL https://claude.ai/install.sh | bash; then
  echo "ERROR: native Claude Code installation failed" >&2
  exit 1
fi
if [[ ! -x "$HOME/.local/bin/claude" ]]; then
  echo "ERROR: native Claude Code installer did not create $HOME/.local/bin/claude" >&2
  exit 1
fi
