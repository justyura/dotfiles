#!/bin/bash

BAR_SIZE=56

# 左侧竖向 SketchyBar：显示时为每个 space 预留左边距，隐藏时清零。
if [[ -f /tmp/yabai_top_padding_hidden ]]; then
    LEFT_PADDING=0
else
    LEFT_PADDING=$BAR_SIZE
fi

/opt/homebrew/bin/yabai -m config external_bar all:0:0

for i in $(/opt/homebrew/bin/yabai -m query --spaces | jq '.[].index'); do
    /opt/homebrew/bin/yabai -m config --space "$i" top_padding "$(cat "$HOME/.cache/focus_bar/top_padding" 2>/dev/null || echo 0)"
    /opt/homebrew/bin/yabai -m config --space "$i" left_padding "$LEFT_PADDING"
done
