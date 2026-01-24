#!/bin/bash

source "$CONFIG_DIR/colors.sh"

if pgrep -f "Tailscale.app" >/dev/null || pgrep -x tailscaled >/dev/null; then
  sketchybar --set "$NAME" icon=󰒄 icon.color=$WHITE
else
  sketchybar --set "$NAME" icon=󰒎 icon.color=$WHITE
fi
