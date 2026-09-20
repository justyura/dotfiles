#!/usr/bin/env sh

yabai=/opt/homebrew/bin/yabai
state_file="/tmp/yabai_top_padding_hidden"

if [ -f "$state_file" ]; then
    rm "$state_file"
    sketchybar --bar hidden=false
    sketchybar --update
else
    touch "$state_file"
    sketchybar --bar hidden=true
fi

# 统一由 update_padding.sh 管理竖向 bar 的左侧预留。
"$HOME/.config/scripts/yabai/update_padding.sh"
