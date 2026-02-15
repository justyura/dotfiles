#!/bin/bash

# 获取当前空间所属的显示器
SPACE_DISPLAY=$(/opt/homebrew/bin/yabai -m query --spaces --space | jq -r '.display')

# 根据显示器应用内边距和 external_bar
if [[ "$SPACE_DISPLAY" == "1" ]]; then
    # MacBook Air (空间 1, 2) - 无 SketchyBar
    /opt/homebrew/bin/yabai -m config external_bar all:0:0
    /opt/homebrew/bin/yabai -m space --padding abs:0:0:0:0
elif [[ "$SPACE_DISPLAY" == "2" ]]; then
    # iPad Pro (空间 3) - 有 SketchyBar
    /opt/homebrew/bin/yabai -m config external_bar all:42:0
    /opt/homebrew/bin/yabai -m space --padding abs:42:0:0:0
fi
