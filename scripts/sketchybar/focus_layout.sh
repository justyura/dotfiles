#!/bin/bash
# The task bar sits flush at the top, independent of the left navigation bar.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
bar="$HOME/.local/bin/focus_bar"
state_dir="$HOME/.cache/focus_bar"
mkdir -p "$state_dir"
offset=0
height=32
if [ "$(cat "$state_dir/layout" 2>/dev/null)" != "$offset" ]; then
    "$bar" --bar y_offset="$offset"
    printf '%s' "$offset" > "$state_dir/layout"
fi
# Used by the existing padding updater so it cannot reset the timer's reservation.
printf '%s' "$height" > "$state_dir/top_padding"
spaces=$(yabai -m query --spaces 2>/dev/null | jq -r '.[] | select(."is-native-fullscreen" == false) | .index')
for space in $spaces; do
    current=$(yabai -m config --space "$space" top_padding 2>/dev/null)
    if [ "$current" != "$height" ]; then yabai -m config --space "$space" top_padding "$height"; fi
done

# Give stationary task content the full usable width; reserve room for controls.
width=$(yabai -m query --displays 2>/dev/null | jq -r '[.[].frame.w] | min // 1200')
chars=$(awk -v w="$width" 'BEGIN { n=int((w-520)/13); if(n<12)n=12; print n }')
if [ "$(cat "$state_dir/task_chars" 2>/dev/null)" != "$chars" ]; then
    "$bar" --set focus.task label.max_chars="$chars" scroll_texts=off
    printf '%s' "$chars" > "$state_dir/task_chars"
fi
