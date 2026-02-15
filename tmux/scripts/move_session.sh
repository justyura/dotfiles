#!/bin/bash
# Move current session left or right in the session list

direction="$1"

if [ -z "$direction" ]; then
  exit 0
fi

python3 "$HOME/.config/tmux/scripts/session_manager.py" move "$direction"
