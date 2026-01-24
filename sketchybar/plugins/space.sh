#!/bin/bash

source "$CONFIG_DIR/colors.sh"

AEROSPACE="/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"

if [ "$SELECTED" = "true" ]; then
  sketchybar --set "$NAME" \
    background.color=$ACCENT_COLOR \
    icon.color=$BLACK \
    label.color=$BLACK
else
  sketchybar --set "$NAME" \
    background.color=$BACKGROUND_1 \
    icon.color=$WHITE \
    label.color=$GREY
fi
