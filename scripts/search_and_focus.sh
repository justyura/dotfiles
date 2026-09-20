#!/bin/bash
"$HOME/.config/scripts/search" && /opt/homebrew/bin/yabai -m space --focus "$(/opt/homebrew/bin/yabai -m query --windows | /opt/homebrew/bin/jq -r 'first(.[] | select(.app == "Safari") | .space)')" 2>/dev/null
exit 0
