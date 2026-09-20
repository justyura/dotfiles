#!/bin/bash

# 悬停高亮：鼠标移入可点击元素时点亮所在组的底块，移出恢复
# 一个组由多个条目拼成（进度条、文字、图标），在成员之间移动会连发 exited/entered，
# 且事件脚本并发执行——所以按成员记录悬停状态，稍等片刻后再按
# “组内是否仍有成员被悬停”统一收敛，避免闪烁
# 也被 standup.sh / ai_usage.sh / space.sh 转调（沿用 sketchybar 传入的 $NAME/$SENDER）

DIR="$HOME/.cache/sketchybar/hover"
mkdir -p "$DIR"

case "$NAME" in
  agents|agents.*)
    GROUP=agents TARGET="" ;; # 行自行着色，仅跟踪悬停状态。
  space.*)
    # Focus renderer owns the background; hover animations must not overwrite it.
    exit 0 ;;
  *)
    # standup.bar → standup.bracket，claude_usage.pct_5h → claude_usage.bracket
    GROUP=${NAME%%.*} TARGET=${NAME%%.*}.bracket
    REST="background.color=0xff292e42 background.border_color=0xff292e42"
    HOVER="background.color=0xff31364d background.border_color=0xff737aa2"
    ;;
esac

case "$SENDER" in
  mouse.entered) touch "$DIR/$NAME" ;;
  mouse.exited) rm -f "$DIR/$NAME" ;;
  mouse.exited.global) rm -f "$DIR/$GROUP" "$DIR/$GROUP".* ;;
  *) exit 0 ;;
esac

sleep 0.05
[ -n "$TARGET" ] || exit 0

if compgen -G "$DIR/$GROUP" >/dev/null || compgen -G "$DIR/$GROUP.*" >/dev/null; then
  sketchybar --animate tanh 8 --set "$TARGET" $HOVER
else
  sketchybar --animate tanh 8 --set "$TARGET" $REST
fi
