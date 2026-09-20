#!/bin/bash

# 快捷键 / 点击打开的「固定预览」弹窗（agent_popup.sh、day_timeline.sh 共用）：
# - 打开时若 bar 处于隐藏状态，先显示 bar（toggle_top_padding.sh），并记在 pin 文件里
# - 固定期间不随鼠标移出收起；再次切换时关闭，若之前是顺带显示的 bar 则一并收回

BAR_HIDDEN_FILE=/tmp/yabai_top_padding_hidden
TOGGLE_BAR="$HOME/.config/scripts/yabai/toggle_top_padding.sh"

# preview_close <弹窗宿主条目> <pin 文件>
preview_close() {
  sketchybar --set "$1" popup.drawing=off
  if [ -f "$2" ]; then
    [ "$(cat "$2")" = 1 ] && [ ! -f "$BAR_HIDDEN_FILE" ] && "$TOGGLE_BAR"
    rm -f "$2"
  fi
}

# preview_toggle <弹窗宿主条目> <pin 文件> <渲染函数名>
preview_toggle() {
  local host=$1 pin=$2 render=$3 opened_bar=0
  if [ "$(sketchybar --query "$host" | jq -r '.popup.drawing')" = on ]; then
    preview_close "$host" "$pin"
    return
  fi
  if [ -f "$BAR_HIDDEN_FILE" ]; then
    "$TOGGLE_BAR"
    opened_bar=1
  fi
  mkdir -p "$(dirname "$pin")"
  echo "$opened_bar" > "$pin"
  "$render"
  sketchybar --set "$host" popup.drawing=on
}
