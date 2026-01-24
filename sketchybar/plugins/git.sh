#!/bin/bash

source "$CONFIG_DIR/colors.sh"

# Get the frontmost app's current directory
FRONTMOST_APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)

# Only show git info for terminal apps
case "$FRONTMOST_APP" in
  "Ghostty"|"Terminal"|"iTerm2"|"WezTerm"|"Alacritty"|"kitty")
    # Try to get PWD from the focused terminal
    # This is a best-effort approach
    PWD_FILE="/tmp/sketchybar_pwd"
    if [ -f "$PWD_FILE" ]; then
      DIR=$(cat "$PWD_FILE")
      if [ -d "$DIR/.git" ] || git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
        BRANCH=$(git -C "$DIR" branch --show-current 2>/dev/null)
        if [ -n "$BRANCH" ]; then
          # Check for uncommitted changes
          if git -C "$DIR" diff --quiet 2>/dev/null && git -C "$DIR" diff --cached --quiet 2>/dev/null; then
            sketchybar --set "$NAME" drawing=on icon= label="$BRANCH" icon.color=$GREEN
          else
            sketchybar --set "$NAME" drawing=on icon= label="$BRANCH*" icon.color=$YELLOW
          fi
          exit 0
        fi
      fi
    fi
    ;;
esac

# Hide if not in a git repo or not in terminal
sketchybar --set "$NAME" drawing=off
