#!/bin/bash

# 检测当前是否使用落格输入法
LOGCG_CHECK=$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleSelectedInputSources | \
    grep -i "com.logcg.inputmethod.LogInputMac3")

if [ -n "$LOGCG_CHECK" ]; then
    # 当前是落格输入法
    DISPLAY="中"
else
    # 当前是ABC或其他输入法
    DISPLAY="EN"
fi

# 更新显示
sketchybar --set input_source label="$DISPLAY"
