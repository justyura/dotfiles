#!/bin/bash

# alt+数字 / shift+alt+数字 切换空间：先立即在 bar 上高亮目标空间，再让 yabai 切换；
# 之后 yabai 的 space_changed 信号会触发 space.sh 校正（窗口占用、空空间隐藏），数字不再等切换动画和信号
# 用法: space_focus.sh <空间号> [move]   （move：先把当前窗口移过去）

N=$1
WHITE=0xff929baa
ACCENT_COLOR=0xffe0e5ec
# zen mode 开着时这个 item 是隐藏的：内容照常更新，但不要把自己重新显示出来（见 plugins/zen.sh）
ZEN_SHOW=on; [ -f "$HOME/.cache/sketchybar/zen_hidden" ] && ZEN_SHOW=off
FOCUSED_FILE="$HOME/.cache/sketchybar/space_focused"
YABAI=/opt/homebrew/bin/yabai

[[ "$N" =~ ^([1-9]|10)$ ]] || exit 1
[ "$2" = move ] && $YABAI -m window --space "$N"
$YABAI -m space --focus "$N" || exit $?
# One owner paints actual focus; no speculative highlight racing the event handler.
exec "$HOME/.config/scripts/sketchybar/space.sh"
