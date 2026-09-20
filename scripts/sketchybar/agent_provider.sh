#!/bin/bash

# Claude / Codex 各自的紧凑状态徽标，显示在对应 app 图标旁。
# 状态优先级：等待处理 > 已完成待查看 > 运行中 > 空闲。

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
source "$PLUGIN_DIR/agent_lib.sh"

case "$NAME" in
  claude_usage.logo) provider=claude ;;
  codex_usage.logo) provider=codex ;;
  *) exit 0 ;;
esac

BLUE=0xff7aa2f7
ORANGE=0xffff9e64
GREEN=0xff9ece6a
GREY=0xff737aa2

running=0
waiting=0
done=0
target=""

while IFS='|' read -r _ _ status _ _ _ file; do
  [ -n "$file" ] || continue
  case "$status" in
    running) running=$((running + 1)) ;;
    waiting) waiting=$((waiting + 1)) ;;
    done) done=$((done + 1)) ;;
    *) continue ;;
  esac
  [ -n "$target" ] || target=$file
done < <(agent_rows "$provider")

total=$((running + waiting + done))
if [ "$waiting" -gt 0 ]; then
  glyph="!" color=$ORANGE
elif [ "$done" -gt 0 ]; then
  glyph="✓" color=$GREEN
elif [ "$running" -gt 0 ]; then
  glyph="●" color=$BLUE
else
  glyph="○" color=$GREY
fi

if [ "$SENDER" = mouse.clicked ] && [ -n "$target" ]; then
  exec "$PLUGIN_DIR/agent_jump.sh" "$target"
fi

[ "$provider" = claude ] && short=Cl || short=Cx
sketchybar --set "$NAME" label="$short $glyph$total" label.color=$color
