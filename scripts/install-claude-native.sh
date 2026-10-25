#!/usr/bin/env bash
# Installs native Claude Code into ~/.local/bin unless a working copy is there.
# Activation runs this, so a failure only warns with the manual command and
# never aborts the rebuild. home.nix supplies curl and the installer's tools
# on PATH; the script itself needs nothing beyond bash builtins.
set -uo pipefail

claude="$HOME/.local/bin/claude"
manual='curl -fsSL https://claude.ai/install.sh | bash'

if [[ -x "$claude" ]] && "$claude" --version >/dev/null 2>&1; then
  exit 0
fi
if [[ -n ${DRY_RUN:-} ]]; then
  echo "Would install native Claude Code in $HOME/.local/bin"
  exit 0
fi

skip() {
  echo "WARNING: native Claude Code was not installed: $1" >&2
  echo "WARNING: the rebuild continues without it; install it by running: $manual" >&2
  exit 0
}

echo "==> Claude Code (native install; it updates itself)"
command -v curl >/dev/null 2>&1 || skip "curl is not on PATH"
installer=$(curl -fsSL https://claude.ai/install.sh) || skip "downloading the installer failed (curl exit $?)"
"$BASH" -c "$installer" </dev/null || skip "the installer exited $?"
if [[ ! -x "$claude" ]] || ! "$claude" --version >/dev/null 2>&1; then
  skip "the installer did not leave a working $claude"
fi
