#!/bin/bash

# 批量更新所有空间指示器（只查询一次 yabai）

WHITE=0xffc0caf5
ACCENT_COLOR=0xff7aa2f7

# 一次性获取所有数据
FOCUSED=$(yabai -m query --spaces | jq -r '[.[] | select(.["has-focus"] == true) | .index] | .[0]')
# 获取每个空间的非 sticky 窗口数，输出格式: "space_index count" 每行一条
OCCUPIED=$(yabai -m query --windows | jq -r '[.[] | select(.["is-sticky"] == false)] | group_by(.space) | .[] | "\(.[0].space) \(length)"')

# 构建一条批量 sketchybar 命令
ARGS=()
for i in {1..10}; do
  COUNT=$(echo "$OCCUPIED" | awk -v s="$i" '$1 == s {print $2}')
  COUNT=${COUNT:-0}

  if [ "$COUNT" -gt 0 ] || [ "$i" = "$FOCUSED" ]; then
    if [ "$i" = "$FOCUSED" ]; then
      COLOR=$ACCENT_COLOR
    else
      COLOR=$WHITE
    fi
    ARGS+=(--set "space.$i" drawing=on icon.color="$COLOR")
  else
    ARGS+=(--set "space.$i" drawing=off)
  fi
done

sketchybar "${ARGS[@]}"
