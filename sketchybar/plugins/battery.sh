#!/bin/bash

# 获取电池信息（单次查询）
BATT_INFO=$(pmset -g batt)
PERCENTAGE=$(echo "$BATT_INFO" | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(echo "$BATT_INFO" | grep 'AC Power')

if [[ -z "$PERCENTAGE" ]]; then
  exit 0
fi

# 选择图标
if [[ -n "$CHARGING" ]]; then
  ICON="󰂄"
elif [[ $PERCENTAGE -gt 80 ]]; then
  ICON="󰁹"
elif [[ $PERCENTAGE -gt 60 ]]; then
  ICON="󰂁"
elif [[ $PERCENTAGE -gt 40 ]]; then
  ICON="󰁿"
elif [[ $PERCENTAGE -gt 20 ]]; then
  ICON="󰁽"
else
  ICON="󰁺"
fi

sketchybar --set battery icon="$ICON" label="${PERCENTAGE}%"
