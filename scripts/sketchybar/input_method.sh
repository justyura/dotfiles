#!/bin/bash

# 输入法状态：中 / 英（鼠须管内部模式，来自 Rime 的 lua/ascii_status.lua）/ US（系统输入法被切到了 U.S.）
# 事件：input_source_change（系统输入法切换通知）、input_method_change（Rime 中英切换时触发）、front_app_switched
# 点击：显示 US 时切回鼠须管；在鼠须管里切换中英（模拟单按右 Control，等同 🌐）

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
HELPER_SRC="$HOME/.config/scripts/sketchybar/helpers/input_source.swift"
HELPER="$HOME/.config/scripts/sketchybar/helpers/input_source"
RIME_STATE="$HOME/.cache/sketchybar/rime_ascii"
SQUIRREL=im.rime.inputmethod.Squirrel.Hans

WHITE=0xffc0caf5
GREY=0xff9aa5ce
ORANGE=0xffff9e64

case "$SENDER" in
  mouse.entered|mouse.exited|mouse.exited.global)
    exec "$PLUGIN_DIR/hover.sh"
    ;;
esac

if [ ! -x "$HELPER" ] || [ "$HELPER_SRC" -nt "$HELPER" ]; then
  swiftc -O "$HELPER_SRC" -o "$HELPER" >/dev/null 2>&1
fi

current=$("$HELPER" 2>/dev/null)

if [ "$SENDER" = mouse.clicked ]; then
  if [[ "$current" == im.rime.inputmethod.Squirrel* ]]; then
    "$HELPER" tap-right-control
  else
    "$HELPER" select "$SQUIRREL"
  fi
  exit 0 # 状态变化会通过事件再触发本脚本刷新
fi

if [[ "$current" == im.rime.inputmethod.Squirrel* ]]; then
  if [ "$(cat "$RIME_STATE" 2>/dev/null)" = 1 ]; then
    sketchybar --set input_method label="英" label.color=$GREY
  else
    sketchybar --set input_method label="中" label.color=$WHITE
  fi
else
  sketchybar --set input_method label="US" label.color=$ORANGE
fi
