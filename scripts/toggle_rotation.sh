#!/bin/bash
# Toggle main display rotation between 0° and 90°

display_id="${DISPLAYPLACER_ID:-}"
display_id_file="$HOME/.config/local/display_id"
if [ -z "$display_id" ] && [ -r "$display_id_file" ]; then
  display_id=$(tr -d '[:space:]' < "$display_id_file")
fi
if [ -z "$display_id" ]; then
  printf 'Set DISPLAYPLACER_ID or write the display ID to %s\n' "$display_id_file" >&2
  exit 1
fi

current=$(/opt/homebrew/bin/displayplacer list | grep "Rotation:" | head -1 | awk '{print $2}')

if [ "$current" = "90" ]; then
  /opt/homebrew/bin/displayplacer "id:$display_id degree:0"
else
  /opt/homebrew/bin/displayplacer "id:$display_id degree:90"
fi
