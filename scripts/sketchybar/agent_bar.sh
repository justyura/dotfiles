#!/bin/bash

# agent 任务（Claude / Codex 图标左侧的一行）：
# - 有待处理会话时显示优先级最高的一个（● 等你处理 / ✓ 已完成 + 会话:窗口），其余计为 +N；点击直接跳到该 tmux pane
#   （右侧空间有限，prompt 摘要只在预览里显示）
# - 没有待处理时显示两家合并的运行中计数（"● N running" / "idle"）；点击打开会话列表
# - 右键点击：打开/关闭会话列表（悬停不再自动弹出）
# - agent_bar.sh jump：直接跳到当前显示的那个待处理会话，没有则什么都不做（alt+a 改由 agent_switch.sh 处理）
# 刷新：update_freq 定时 + hook 触发的 agent_status_change 事件

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
source "$PLUGIN_DIR/agent_lib.sh"

WHITE=0xffc0caf5
GREY=0xff737aa2
BLUE=0xff7aa2f7
ORANGE=0xffff9e64
GREEN=0xff9ece6a

case "$SENDER" in
  mouse.entered|mouse.exited|mouse.exited.global)
    exec "$PLUGIN_DIR/agent_popup.sh"
    ;;
  mouse.clicked)
    # 右键：打开/关闭会话列表
    [ "$BUTTON" = right ] && exec "$PLUGIN_DIR/agent_popup.sh" click_toggle
    ;;
esac

pending=()
running=0
while IFS='|' read -r _ _ status _ loc prompt f; do
  case "$status" in
    waiting|done) pending+=("$status|$loc|$prompt|$f") ;;
    running) running=$((running + 1)) ;;
  esac
done < <(agent_rows_all)

if [ ${#pending[@]} -gt 0 ]; then
  IFS='|' read -r status loc prompt f <<< "${pending[0]}"

  if [ "$SENDER" = mouse.clicked ] || [ "$1" = jump ]; then
    exec "$PLUGIN_DIR/agent_jump.sh" "$f"
  fi

  if [ "$status" = waiting ]; then glyph="●" color=$ORANGE; else glyph="✓" color=$GREEN; fi
  label="${#pending[@]}"
  sketchybar --set agents.icon label="$glyph" label.color=$color \
    --set agents.task icon.drawing=off label="$label" label.color=$WHITE label.padding_left=0
else
  [ "$1" = jump ] && exit 0
  if [ "$SENDER" = mouse.clicked ]; then
    exec "$PLUGIN_DIR/agent_popup.sh" click_toggle
  fi

  if [ "$running" -gt 0 ]; then
    sketchybar --set agents.icon label="●" label.color=$BLUE \
      --set agents.task icon.drawing=off label="$running" label.color=$GREY label.padding_left=0
  else
    sketchybar --set agents.icon label="○" label.color=$GREY \
      --set agents.task icon.drawing=off label="0" label.color=$GREY label.padding_left=0
  fi
fi
