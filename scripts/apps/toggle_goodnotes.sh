#!/bin/bash
YABAI="/opt/homebrew/bin/yabai"
JQ="/opt/homebrew/bin/jq"

current_app="$("$YABAI" -m query --windows --window 2>/dev/null | "$JQ" -r '.app')"

if [ "$current_app" = "Goodnotes" ]; then
    "$YABAI" -m space --focus recent
else
    target_space="$("$YABAI" -m query --windows | "$JQ" -r 'first(.[] | select(.app == "Goodnotes") | .space)')"
    if [ -n "$target_space" ] && [ "$target_space" != "null" ]; then
        "$YABAI" -m space --focus "$target_space"
    fi
fi
