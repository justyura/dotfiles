#!/bin/bash

# 使用系统快捷键切换输入法
# 默认快捷键是 Control+Space 或 Control+Option+Space
osascript -e 'tell application "System Events" to key code 49 using control down'

# 等待切换完成后更新显示
sleep 0.3
sketchybar --trigger input_source_update
