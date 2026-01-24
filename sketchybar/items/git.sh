#!/bin/bash

git_branch=(
  icon=
  icon.color=$GREEN
  label.drawing=on
  script="$PLUGIN_DIR/git.sh"
  update_freq=10
)

sketchybar --add item git_branch right \
           --set git_branch "${git_branch[@]}"
