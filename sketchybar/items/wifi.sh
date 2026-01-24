#!/bin/bash

wifi=(
  icon=󰖩
  icon.color=$GREEN
  label.drawing=off
  script="$PLUGIN_DIR/wifi.sh"
  update_freq=30
)

sketchybar --add item wifi right \
           --set wifi "${wifi[@]}"
