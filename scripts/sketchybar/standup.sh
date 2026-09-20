#!/bin/bash
# 自动活动计时；单击打开/关闭面板，不改变计时状态。
source "$HOME/.config/sketchybar/settings.sh"
export STANDUP_WORK_MIN STANDUP_BREAK_MIN STANDUP_IDLE_SEC STANDUP_CAMERA STANDUP_CAMERA_INTERVAL STANDUP_SOUND
NOW=$(date +%s)
ACTION=()
case "$1" in
  start-break)
    ACTION=(start-break)
    SENDER=manual_action ;;
  break)
    ACTION=(toggle-break)
    SENDER=manual_action ;;
  close) sketchybar --set standup popup.drawing=off; exit 0 ;;
  history)
    sketchybar --set standup popup.drawing=off
    exec /usr/bin/python3 "$HOME/.config/scripts/things/things_now_session.py" report ;;
esac
if [ "$SENDER" = mouse.clicked ]; then
    # 触控板普通单击和右键都可开关。
      if [ "$(sketchybar --query standup | jq -r '.popup.drawing')" = on ]; then
        sketchybar --set standup popup.drawing=off
      else
        # 每次生成新文件名，避免 sketchybar 按路径缓存旧图
        HEATMAP_DIR="$HOME/.cache/sketchybar/heatmap"
        mkdir -p "$HEATMAP_DIR"
        rm -f "$HEATMAP_DIR"/*.png
        IMG="$HEATMAP_DIR/focus-$NOW.png"
        SUMMARY=$(python3 "$HOME/.config/scripts/sketchybar/focus_heatmap.py" "$FOCUS_DIR" "$IMG" \
          "$FOCUS_HEATMAP_WEEKS" "$FOCUS_LEVEL_HOURS" 2>/dev/null)
        sketchybar --set standup.heatmap.title label="Focus time · last $FOCUS_HEATMAP_WEEKS weeks" \
          --set standup.heatmap background.image="$IMG" \
          --set standup.heatmap.summary label="${SUMMARY:-No focus data yet}" \
          --set standup popup.drawing=on
      fi
      exit 0
fi
case "$SENDER" in
  mouse.entered|mouse.exited|mouse.exited.global)
    "$HOME/.config/scripts/sketchybar/hover.sh"
    # Allow crossing the small gap from the reminder to its history link.
    [ "$SENDER" = mouse.entered ] || sleep 0.35
    if ! compgen -G "$HOME/.cache/sketchybar/hover/standup*" >/dev/null; then
      sketchybar --set standup popup.drawing=off
    fi
    exit 0
    ;;
esac

DATA=$(python3 "$HOME/.config/scripts/sketchybar/standup_auto.py" "${ACTION[@]}") || exit 0
IFS='|' read -r GLYPH LABEL COLOR IMAGE BREAK_LABEL < <(printf '%s' "$DATA" | jq -r '[.glyph,.label,.color,.image,.break_label] | join("|")')
[ -n "$GLYPH" ] || exit 0
sketchybar --set standup icon="$GLYPH" icon.color="$COLOR" label="$GLYPH $LABEL" label.color="$COLOR" update_freq=5 \
  --set standup.bar background.image="$IMAGE" \
  --set standup.break label="$BREAK_LABEL"
[ "$SENDER" = manual_action ] && sketchybar --set standup popup.drawing=off
