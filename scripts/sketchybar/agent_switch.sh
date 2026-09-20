#!/bin/bash

# option+a 打开 Agent 会话选择器；在 skhd agents 模式中：
# j/k 上下选择，Enter 跳转，Esc 取消。

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
STATE_DIR="$HOME/.cache/sketchybar"
SEQUENCE="$STATE_DIR/agent_switch_sequence"
SELECTED="$STATE_DIR/agent_switch_selected"

select_index() {
  local index=$1 total
  [ -s "$SEQUENCE" ] || return 1
  total=$(wc -l < "$SEQUENCE" | tr -d ' ')
  [ "$index" -lt 1 ] && index=$total
  [ "$index" -gt "$total" ] && index=1
  printf '%s\n' "$index" > "$SELECTED.tmp" && mv "$SELECTED.tmp" "$SELECTED"
  "$PLUGIN_DIR/agent_popup.sh" select "$index"
}

case "${1:-open}" in
  open)
    mkdir -p "$STATE_DIR"
    source "$PLUGIN_DIR/agent_lib.sh"
    agent_session_lines > "$SEQUENCE"
    if [ ! -s "$SEQUENCE" ]; then
      rm -f "$SELECTED"
      "$PLUGIN_DIR/agent_popup.sh" render 0 prepared
      "$PLUGIN_DIR/agent_popup.sh" switcher_show
      exit 0
    fi

    count=$(wc -l < "$SEQUENCE" | tr -d ' ')
    if [ "$count" -gt 1 ] && [ "$(head -1 "$SEQUENCE" | cut -f7)" = current ]; then
      selected=2
    else
      selected=1
    fi
    printf '%s\n' "$selected" > "$SELECTED"
    "$PLUGIN_DIR/agent_popup.sh" render "$selected" prepared
    "$PLUGIN_DIR/agent_popup.sh" switcher_show
    ;;
  down)
    select_index $(( $(cat "$SELECTED" 2>/dev/null || echo 1) + 1 ))
    ;;
  up)
    select_index $(( $(cat "$SELECTED" 2>/dev/null || echo 1) - 1 ))
    ;;
  enter)
    index=$(cat "$SELECTED" 2>/dev/null || echo 1)
    file=$(sed -n "${index}p" "$SEQUENCE" 2>/dev/null | cut -f1)
    "$PLUGIN_DIR/agent_popup.sh" switcher_hide
    rm -f "$SELECTED"
    [ -n "$file" ] && exec "$PLUGIN_DIR/agent_jump.sh" "$file"
    ;;
  close)
    "$PLUGIN_DIR/agent_popup.sh" switcher_hide
    rm -f "$SELECTED"
    ;;
esac
