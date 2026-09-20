#!/bin/bash

# 任务清单弹窗里点击待办（弹窗行的 click_script）：
# - 左键：勾选完成 / 取消完成，与在 Things 里点复选框一致；弹窗行原地更新，不关闭清单
# - 右键：在 Things 中打开该待办（things_open.sh）
# 用法: things_toggle.sh <待办 id>

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"

if [ "$BUTTON" = right ]; then
  exec "$HOME/.config/scripts/things/things_open.sh" "$1"
fi
exec "$HOME/.config/scripts/things/things_nav.sh" toggle_id "$1"
