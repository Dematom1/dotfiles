#!/bin/bash

AEROSPACE="/opt/homebrew/bin/aerospace"

# Show only the current workspace
sketchybar --add event aerospace_workspace_change

current_space=(
  icon.font="SF Pro:Semibold:14.0"
  icon.color=$WHITE
  icon.padding_left=10
  icon.padding_right=6
  label.font="SF Pro:Semibold:14.0"
  label.color=$GREY
  label.padding_right=10
  background.color=$BACKGROUND_1
  background.corner_radius=5
  background.height=24
  script="$PLUGIN_DIR/spaces.sh"
)

sketchybar --add item current_space left \
           --set current_space "${current_space[@]}" \
           --subscribe current_space aerospace_workspace_change

# Trigger initial update
$PLUGIN_DIR/spaces.sh
