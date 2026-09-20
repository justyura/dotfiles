#!/bin/bash

# 批量更新所有空间指示器（只查询一次 yabai）

# 悬停事件交给 hover.sh（space.1 挂的是本脚本）
case "$SENDER" in
  mouse.entered|mouse.exited|mouse.exited.global)
    exec "$HOME/.config/scripts/sketchybar/hover.sh"
    ;;
esac

WHITE=0xff929baa
# zen mode 开着时这个 item 是隐藏的：内容照常更新，但不要把自己重新显示出来（见 plugins/zen.sh）
ZEN_SHOW=on; [ -f "$HOME/.cache/sketchybar/zen_hidden" ] && ZEN_SHOW=off
ACCENT_COLOR=0xffe0e5ec
FOCUSED_FILE="$HOME/.cache/sketchybar/space_focused"   # 当前聚焦空间（space_focus.sh 用来立即取消上一个高亮）

# 串行执行：多个事件会同时触发本脚本，只让一个实例运行；其余只标记 dirty，
# 运行中的实例会在结束前重新查询一次，保证最后写到 bar 上的是最新状态
LOCK="$HOME/.cache/sketchybar/space.lock"
DIRTY="$HOME/.cache/sketchybar/space.dirty"
mkdir -p "$HOME/.cache/sketchybar"
touch "$DIRTY"
find "$LOCK" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null   # 清理异常退出留下的锁
mkdir "$LOCK" 2>/dev/null || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

while [ -f "$DIRTY" ]; do
rm -f "$DIRTY"

# 一次性获取所有数据
SPACES=$(yabai -m query --spaces) || continue
FOCUSED=$(printf '%s' "$SPACES" | jq -r '[.[] | select(.["has-focus"] == true) | .index] | .[0]')
[[ "$FOCUSED" =~ ^[0-9]+$ ]] || continue
# 获取每个空间的非 sticky 窗口数，输出格式: "space_index count" 每行一条
OCCUPIED=$(yabai -m query --windows | jq -r '[.[] | select(.["is-sticky"] == false)] | group_by(.space) | .[] | "\(.[0].space) \(length)"')

# 构建一条批量 sketchybar 命令（每次都完整设置全部空间：多个事件会并发触发本脚本，
# 只更新“有变化”的空间会让较晚完成的旧结果覆盖新结果，数字就会错）
ARGS=()
for i in {1..10}; do
  COUNT=$(echo "$OCCUPIED" | awk -v s="$i" '$1 == s {print $2}')
  COUNT=${COUNT:-0}

  # Keep real spaces in fixed slots; only their emphasis changes.
  if printf '%s' "$SPACES" | jq -e --argjson n "$i" 'any(.[]; .index == $n)' >/dev/null; then
    if [ "$i" = "$FOCUSED" ]; then
      COLOR=$ACCENT_COLOR
    else
      COLOR=$WHITE
      [ "$COUNT" -gt 0 ] || COLOR=0xff626d80
    fi
    BG=0x00292e42
    [ "$i" = "$FOCUSED" ] && BG=0xff303b45
    ARGS+=(--set "space.$i" drawing=$ZEN_SHOW icon.color="$COLOR" background.color="$BG")
  else
    ARGS+=(--set "space.$i" drawing=off)
  fi
done

SIGNATURE="${ARGS[*]}"
if [ "$SENDER" = forced ] || [ "$SIGNATURE" != "$(cat "$HOME/.cache/sketchybar/space.rendered" 2>/dev/null)" ]; then
  sketchybar "${ARGS[@]}" && printf '%s' "$SIGNATURE" > "$HOME/.cache/sketchybar/space.rendered"
fi
echo "$FOCUSED" > "$FOCUSED_FILE"
done
