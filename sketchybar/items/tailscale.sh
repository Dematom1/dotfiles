#!/bin/bash

tailscale=(
  icon=󰒄
  label.drawing=off
  script="$PLUGIN_DIR/tailscale.sh"
  update_freq=10
)

sketchybar --add item tailscale right \
           --set tailscale "${tailscale[@]}"
