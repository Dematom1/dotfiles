#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/Code/dotfiles
exec sudo darwin-rebuild switch --flake ~/Code/dotfiles#MacBook
