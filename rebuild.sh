#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# The config hardcodes ~/Code/dotfiles, so point that path here - but only when
# the repo lives elsewhere, or ln would nest a stray symlink inside the repo.
if [[ "$DIR" != "$HOME/Code/dotfiles" ]]; then
  mkdir -p "$HOME/Code"
  ln -sfn "$DIR" "$HOME/Code/dotfiles"
fi

# Which machine this is: "personal" (default) or "work". Both configs are
# committed under ./hosts, so either Mac rebuilds straight from git. This
# one-word marker just picks which to build. See README.md for safe setup.
PROFILE="personal"
if [[ -f "$HOME/.config/dotfiles-profile" ]]; then
  PROFILE="$(<"$HOME/.config/dotfiles-profile")"
fi

exec sudo darwin-rebuild switch --flake ~/Code/dotfiles#"$PROFILE"
