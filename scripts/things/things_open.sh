#!/bin/bash

# 点击 Things 待办：在当前桌面呼出原生浮窗，并定位待办。
# 用法: things_open.sh <待办 id>

# 收起清单弹窗；若处于 alt+k 键盘模式，先退出该模式（由 things_nav.sh leave 收起弹窗）
source "$HOME/.config/scripts/things/things_lib.sh"
source "$HOME/.config/scripts/sketchybar/preview_lib.sh"
if [ -f "$THINGS_NAV" ]; then
  "$HOME/.config/scripts/things/things_nav.sh" exit_mode
else
  preview_close timeline "$THINGS_PIN"
fi

/bin/bash "$HOME/.config/scripts/things/toggle_things.sh" "$1"
