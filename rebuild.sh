#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# The config hardcodes ~/Code/dotfiles, so point that path here - but only when
# the repo lives elsewhere, or ln would nest a stray symlink inside the repo.
if [[ "$DIR" != "$HOME/Code/dotfiles" ]]; then
  mkdir -p "$HOME/Code"
  if [[ -e "$HOME/Code/dotfiles" && ! -L "$HOME/Code/dotfiles" ]]; then
    echo "Refusing to replace existing non-symlink: $HOME/Code/dotfiles" >&2
    exit 1
  fi
  ln -sfn "$DIR" "$HOME/Code/dotfiles"
fi

# Which machine this is: "personal" (default) or "work". Both configs are
# committed under ./hosts, so either Mac rebuilds straight from git. This
# one-word marker just picks which to build. See README.md for safe setup.
PROFILE_FILE="$HOME/.config/dotfiles-profile"
PROFILE="personal"
if [[ -f "$PROFILE_FILE" ]]; then
  PROFILE="$(<"$PROFILE_FILE")"
fi
case "$PROFILE" in
  personal|work) ;;
  *)
    echo "Unsupported dotfiles profile '$PROFILE' in $PROFILE_FILE; expected 'personal' or 'work'." >&2
    exit 1
    ;;
esac

# The flake's host mapping is the username source of truth. Refuse to activate a
# profile for another macOS account rather than writing into the wrong home.
if ! EXPECTED_USER="$(nix eval --raw "$DIR#darwinConfigurations.${PROFILE}.config.system.primaryUser")"; then
  echo "Unable to resolve the macOS account for dotfiles profile '$PROFILE'." >&2
  exit 1
fi
CURRENT_USER="$(id -un)"
if [[ "$CURRENT_USER" != "$EXPECTED_USER" ]]; then
  echo "Dotfiles profile '$PROFILE' targets macOS account '$EXPECTED_USER', but the current account is '$CURRENT_USER'." >&2
  echo "Select the matching profile in $PROFILE_FILE before rebuilding." >&2
  exit 1
fi

# On a fresh machine nix-darwin isn't installed yet, so `darwin-rebuild` won't
# exist. Bootstrap it once via `nix run` (pinning the same nix-darwin release as
# flake.nix); that first switch installs darwin-rebuild for later rebuilds.
if command -v darwin-rebuild >/dev/null 2>&1; then
  exec sudo darwin-rebuild switch --flake "$HOME/Code/dotfiles#$PROFILE"
fi
exec sudo nix run nix-darwin/nix-darwin-26.05#darwin-rebuild -- switch --flake "$HOME/Code/dotfiles#$PROFILE"
