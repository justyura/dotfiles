#!/usr/bin/env sh

yabai=/opt/homebrew/bin/yabai
state_file="/tmp/yabai_top_padding_hidden"

if [ -f "$state_file" ]; then
    rm "$state_file"
    sketchybar --bar hidden=false
    p=28
else
    touch "$state_file"
    sketchybar --bar hidden=true
    p=0
fi

for i in $($yabai -m query --spaces | jq '.[].index'); do
    $yabai -m config --space "$i" top_padding "$p"
done
