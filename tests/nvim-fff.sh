#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

XDG_CONFIG_HOME="$repo" nvim --headless -c "luafile $repo/tests/nvim-fff.lua"
