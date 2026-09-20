#!/bin/bash

# Zen mode：bar 上只留任务进度（timeline / timeline.project，不含 Things 图标）、站立计时（standup*）、
# 输入法（input_method*）和时钟（calendar），其余 item 全部隐藏。
# 进入时把「当前可见、且不属于保留组」的 item 快照进状态文件，退出时只还原快照里的这些 ——
# sketchybarrc 里 timeline.bracket / standup.gap / input_method.bracket 等本来就是 drawing=off，
# 退出时不能无脑全开。弹窗里的 item（position=popup）一律不动，否则会把清单行、热力图一起关掉。
# 用法: zen.sh toggle | apply（apply 供 sketchybarrc 重载后恢复状态）

ZEN_STATE="$HOME/.cache/sketchybar/zen_hidden"   # 文件存在=zen 开着；内容=被它隐藏的 item 名
ZEN_ON_COLOR=0xff9ece6a                          # 开：强调绿
ZEN_OFF_COLOR=0xff565f89                         # 关：暗色

# 保留组：zen 按钮、PhotoShare 上传、任务进度、站立计时、输入法、时钟（弹窗子项由 hideable 跳过，不受影响）
keep() {
  case "$1" in
    zen|photoshare_upload|timeline|timeline.project|timeline.bracket|standup|standup.*|input_method|input_method.*|calendar) return 0 ;;
    *) return 1 ;;
  esac
}

# 当前 bar 上可见、且不在保留组里的 item（弹窗子项跳过）
hideable() {
  local item info
  for item in $(sketchybar --query bar | jq -r '.items[]'); do
    keep "$item" && continue
    info=$(sketchybar --query "$item" | jq -r '.geometry.position + "|" + .geometry.drawing')
    case "$info" in
      popup\|*) ;;
      *\|on) printf '%s\n' "$item" ;;
    esac
  done
}

set_drawing() { # set_drawing on|off <item>...
  local state=$1 args=() item
  shift
  for item in "$@"; do args+=(--set "$item" drawing=$state); done
  [ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}"
}

enter() {
  local items=()
  while IFS= read -r item; do [ -n "$item" ] && items+=("$item"); done < <(hideable)
  mkdir -p "$(dirname "$ZEN_STATE")"
  printf '%s\n' "${items[@]}" > "$ZEN_STATE"
  set_drawing off "${items[@]}"
  sketchybar --set zen icon.color=$ZEN_ON_COLOR
}

leave() {
  local items=() item
  while IFS= read -r item; do [ -n "$item" ] && [ "$item" != timeline.things ] && items+=("$item"); done < "$ZEN_STATE" 2>/dev/null
  rm -f "$ZEN_STATE"
  set_drawing on "${items[@]}"
  sketchybar --set zen icon.color=$ZEN_OFF_COLOR
  sketchybar --trigger space_change   # zen 期间空间的窗口占用可能变了，让 space.sh 重新校正一次
}

case "${1:-toggle}" in
  toggle) [ -f "$ZEN_STATE" ] && leave || enter ;;
  apply)
    # 重载后 item 都是可见的：zen 开着就按当前 item 重新快照一次，否则只把按钮颜色刷对
    if [ -f "$ZEN_STATE" ]; then enter; else sketchybar --set zen icon.color=$ZEN_OFF_COLOR; fi
    ;;
esac
