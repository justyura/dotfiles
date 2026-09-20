#!/bin/bash

# 时间轴右侧：当前 tmux 会话同名的 Things 3 项目里的第一条未完成待办，点击在 Things 中打开
# 没有对应项目 / 没有待办 / Things 未运行时隐藏

source "$HOME/.config/scripts/things/things_lib.sh"

case "$SENDER" in
  mouse.entered|mouse.exited|mouse.exited.global)
    exec "$HOME/.config/scripts/sketchybar/hover.sh"
    ;;
esac

PROJECT=$(current_project)
[ -n "$PROJECT" ] && TODOS=$(things_todos "$PROJECT")
FIRST=$(head -1 <<< "$TODOS")

if [ -z "$PROJECT" ] || [ -z "$FIRST" ] || [ "$FIRST" = NOT_RUNNING ] || [ "$FIRST" = NO_PROJECT ]; then
  sketchybar --set things drawing=off
  exit 0
fi

IFS=$'\t' read -r ID NAME_TEXT <<< "$FIRST"
sketchybar --set things drawing=on label="$NAME_TEXT" click_script="$(things_open_cmd "$ID")"
