#!/bin/bash

AEROSPACE="/opt/homebrew/bin/aerospace"
source "$CONFIG_DIR/colors.sh"

# Get focused workspace
FOCUSED=$($AEROSPACE list-workspaces --focused)

sketchybar --set current_space icon="$FOCUSED"
