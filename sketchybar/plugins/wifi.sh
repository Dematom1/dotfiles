#!/bin/bash

source "$CONFIG_DIR/colors.sh"

IP=$(ipconfig getifaddr en0 2>/dev/null)

if [ -n "$IP" ]; then
  sketchybar --set "$NAME" icon=󰖩 icon.color=$WHITE
else
  sketchybar --set "$NAME" icon=󰖪 icon.color=$WHITE
fi
