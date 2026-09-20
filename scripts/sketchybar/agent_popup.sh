#!/bin/bash

# agent 会话面板：从中央独立 Agent 管理器弹出 Claude / Codex 会话列表。
# 每行：状态图标（扇区逐帧填满 = 运行中转圈，打钩 = 已完成，感叹号 = 等你处理）+ 来源 app 图标 + 会话:窗口（粗体，方便查找）+ prompt · 时长
# 行顺序见 agent_lib.sh 的 agent_session_lines（当前会话在最前）
#
# 打开方式（悬停不会自动弹出，避免光标划过 bar 时挡住输入）：
# - agent_popup.sh click_toggle（左键点击无待处理的任务项 / 右键点击任务项）：打开或关闭；
#   鼠标离开任务项和面板 0.3s 后自动收起
# - agent_popup.sh toggle：固定显示，不随鼠标收起（preview_lib.sh）
# - option+a（agent_switch.sh）：render <选中行> 生成并高亮 → select <行> 移动高亮 → switcher_show / switcher_hide
# 面板打开时才重建行（避免鼠标在面板内移动时反复重建）；popup 内条目不支持 --move，所以整体重建

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
HOVER_DIR="$HOME/.cache/sketchybar/hover"
PIN_FILE="$HOME/.cache/sketchybar/agent_preview_pinned"
SEQUENCE="$HOME/.cache/sketchybar/agent_switch_sequence"   # 当前面板各行对应的会话（agent_session_lines 的输出）
SELECTED="$HOME/.cache/sketchybar/agent_switch_selected"   # option+a 选中的行号（从 1 开始）；存在即表示切换器进行中
SPINNER_PID="$HOME/.cache/sketchybar/agent_popup_spinner_pid"
source "$PLUGIN_DIR/agent_lib.sh"
source "$PLUGIN_DIR/preview_lib.sh"

WHITE=0xffeef1ff
GREY=0xff9aa5ce
BLUE=0xff7aa2f7
ORANGE=0xffff9e64
GREEN=0xff9ece6a
ROW_BG=0x00292e42
HOVER_BG=0xff292e42
SELECT_BG=0xff3b4261
CURRENT_BORDER=0xff565f89

GROUP=agents
HOST=agents.switcher

# 状态图标（Hack Nerd Font：nf-md-check_circle / alert_circle / circle_slice_1..8）
# 一行只有 icon/label 两段文字、各自一种字体：icon 留给粗体项目名，状态图标由 helpers/status_icons
# 预渲染成 PNG（done / seen / waiting / running_0..7），作为行的 background.image 显示
GLYPH_DONE=$(printf '\363\260\227\240')
GLYPH_WAITING=$(printf '\363\260\200\250')
SPINNER_FRAMES=("$(printf '\363\260\252\236')" "$(printf '\363\260\252\237')" "$(printf '\363\260\252\240')" "$(printf '\363\260\252\241')" "$(printf '\363\260\252\242')" "$(printf '\363\260\252\243')" "$(printf '\363\260\252\244')" "$(printf '\363\260\252\245')")
STATUS_ICON_DIR="$HOME/.cache/sketchybar/agent_status_icons"
STATUS_ICONS_SRC="$HOME/.config/scripts/sketchybar/helpers/status_icons.swift"
STATUS_ICONS_BIN="$HOME/.config/scripts/sketchybar/helpers/status_icons"

# 状态图标 PNG 不存在或本脚本/生成器改过（字形、颜色可能变了）时重新生成
ensure_status_icons() {
  local stamp="$STATUS_ICON_DIR/.stamp" gen=() n
  [ "$stamp" -nt "$STATUS_ICONS_SRC" ] && [ "$stamp" -nt "$PLUGIN_DIR/agent_popup.sh" ] && return 0
  if [ ! -x "$STATUS_ICONS_BIN" ] || [ "$STATUS_ICONS_SRC" -nt "$STATUS_ICONS_BIN" ]; then
    swiftc -O "$STATUS_ICONS_SRC" -o "$STATUS_ICONS_BIN" >/dev/null 2>&1 || return 1
  fi
  gen=(done "$GLYPH_DONE" $GREEN seen "$GLYPH_DONE" $GREY waiting "$GLYPH_WAITING" $ORANGE)
  for n in "${!SPINNER_FRAMES[@]}"; do gen+=("running_$n" "${SPINNER_FRAMES[$n]}" $BLUE); done
  "$STATUS_ICONS_BIN" "$STATUS_ICON_DIR" "${gen[@]}" && touch "$stamp"
}

# 高亮某一行（切换器）并给当前会话那一行加边框
row_style() { # row_style <行号从0> <是否选中 0|1> <是否当前 0|1>
  local bg=$ROW_BG border=0
  [ "$2" = 1 ] && bg=$SELECT_BG
  [ "$3" = 1 ] && [ "$2" = 0 ] && border=1
  echo "background.color=$bg background.border_width=$border background.border_color=$CURRENT_BORDER"
}

render() { # render [选中行号，从 1 开始]
  local selected=${1:-0} old=() args=() i=0 running_rows=() f status loc bundle prompt when flag status_icon is_current
  ensure_status_icons
  while read -r item; do [ -n "$item" ] && old+=(--remove "$item"); done < <(
    sketchybar --query "$HOST" | jq -r '.popup.items[]?'
  )
  [ ${#old[@]} -gt 0 ] && sketchybar "${old[@]}" >/dev/null 2>&1

  mkdir -p "$(dirname "$SEQUENCE")"
  [ "$2" = prepared ] || agent_session_lines > "$SEQUENCE"

  args+=(--add item "$GROUP.row_header" "popup.$HOST"
    --set "$GROUP.row_header" icon.drawing=off label="Agents" label.font="SF Pro:Semibold:13.0" label.color=$GREY
      label.padding_left=12 label.padding_right=12 background.height=30 script="$PLUGIN_DIR/agent_popup.sh"
    --subscribe "$GROUP.row_header" mouse.entered mouse.exited)

  while IFS=$'\t' read -r f status loc bundle prompt when flag; do
    [ -n "$f" ] || continue
    case "$status" in
      running) status_icon=running_0; running_rows+=("$GROUP.row.$i") ;;
      waiting|done) status_icon=$status ;;
      *) status_icon=seen ;;
    esac
    [ "$flag" = current ] && is_current=1 || is_current=0
    item="$GROUP.row.$i"
    # 横向排布（图片按 32pt 基准高度 × scale 显示，从所在背景左边缘 + image.padding_left 开始画）：
    # 状态图标 12–30（行背景图）→ app 图标 36–55（icon 背景图）→ 粗体项目名从 66 开始 → prompt · 时长
    args+=(--add item "$item" "popup.$HOST"
      --set "$item"
        icon="$loc" icon.color=$WHITE icon.font="SF Pro:Semibold:14.0"
        icon.width=260 icon.align=left
        icon.padding_left=66 icon.padding_right=14
        icon.background.drawing=on icon.background.color=0x00000000
        icon.background.image="app.$bundle" icon.background.image.scale=0.6 icon.background.image.padding_left=36
        icon.background.image.drawing=on
        label="$([ "$is_current" = 1 ] && echo '● 当前   ')$when"
        label.color=$GREY label.font="SF Pro:Medium:12.0" label.padding_right=14
        label.max_chars=32 label.width=200 label.align=right
        background.corner_radius=5 background.height=30
        background.image="$STATUS_ICON_DIR/$status_icon.png" background.image.scale=0.55
        background.image.padding_left=12 background.image.drawing=on
        $(row_style "$i" "$([ $((i + 1)) = "$selected" ] && echo 1 || echo 0)" "$is_current")
        padding_left=6 padding_right=6
        click_script="$PLUGIN_DIR/agent_jump.sh $f"
        script="$PLUGIN_DIR/agent_popup.sh"
      --subscribe "$item" mouse.entered mouse.exited)
    args+=(--add item "$GROUP.detail.$i" "popup.$HOST"
      --set "$GROUP.detail.$i"
        icon.drawing=off label="${prompt:-(no prompt)}"
        label.font="SF Pro:Medium:12.0" label.color=$GREY label.max_chars=64
        label.width=460 label.align=left label.padding_left=66 label.padding_right=14
        background.height=24 background.corner_radius=5
        $(row_style "$i" "$([ $((i + 1)) = "$selected" ] && echo 1 || echo 0)" 0)
        padding_left=6 padding_right=6
        click_script="$PLUGIN_DIR/agent_jump.sh $f")
    i=$((i + 1))
  done < "$SEQUENCE"

  if [ "$i" -eq 0 ]; then
    args+=(--add item "$GROUP.row.0" "popup.$HOST"
      --set "$GROUP.row.0" icon.drawing=off label="No active sessions" label.color=$GREY
        label.font="SF Pro:Medium:15.0" label.padding_left=12 label.padding_right=12 background.height=32)
  fi

  args+=(--add item "$GROUP.footer" "popup.$HOST"
    --set "$GROUP.footer" icon.drawing=off label="j/k 选择   ·   ↵ 跳转   ·   Esc 关闭"
    label.font="SF Pro:Medium:11.0" label.color=$GREY
    label.padding_left=12 label.padding_right=12 background.height=28)
  sketchybar "${args[@]}"
}

# 切换器移动高亮：只改各行背景
select_row() { # select_row <行号，从 1 开始>
  local args=() i=0 f flag
  while IFS=$'\t' read -r f _ _ _ _ _ flag; do
    [ -n "$f" ] || continue
    args+=(--set "$GROUP.row.$i" $(row_style "$i" "$([ $((i + 1)) = "$1" ] && echo 1 || echo 0)" "$([ "$flag" = current ] && echo 1 || echo 0)"))
    args+=(--set "$GROUP.detail.$i" $(row_style "$i" "$([ $((i + 1)) = "$1" ] && echo 1 || echo 0)" 0))
    i=$((i + 1))
  done < "$SEQUENCE"
  [ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}"
}

# 运行中行的转圈动画：面板打开期间逐帧切换状态图标；面板关闭或重新生成时停止
start_spinner() {
  [ -f "$SPINNER_PID" ] && kill "$(cat "$SPINNER_PID")" 2>/dev/null
  rm -f "$SPINNER_PID"
  [ $# -gt 0 ] || return 0
  (
    frame=0
    sleep 0.15
    while [ "$(sketchybar --query "$HOST" 2>/dev/null | jq -r '.popup.drawing')" = on ]; do
      frame=$(((frame + 1) % ${#SPINNER_FRAMES[@]}))
      set_args=()
      for row in "$@"; do set_args+=(--set "$row" background.image="$STATUS_ICON_DIR/running_$frame.png"); done
      sketchybar "${set_args[@]}" 2>/dev/null || break
      sleep 0.15
    done
    rm -f "$SPINNER_PID"
  ) >/dev/null 2>&1 &
  echo $! > "$SPINNER_PID"
}

case "$1" in
  toggle)
    preview_toggle "$HOST" "$PIN_FILE" render
    exit 0
    ;;
  click_toggle)
    if [ "$(sketchybar --query "$HOST" | jq -r '.popup.drawing')" = on ]; then
      preview_close "$HOST" "$PIN_FILE"
    else
      render   # render 内已启动转圈动画（等面板显示后开始逐帧切换）
      sketchybar --set "$HOST" popup.drawing=on
    fi
    exit 0
    ;;
  render)
    render "$2" "$3"
    exit 0
    ;;
  select)
    select_row "$2"
    exit 0
    ;;
  switcher_show)
    # option+a 按住：bar 隐藏时顺带显示，固定面板不随鼠标收起
    opened_bar=0
    if [ -f "$BAR_HIDDEN_FILE" ]; then "$TOGGLE_BAR" >/dev/null 2>&1; opened_bar=1; fi
    echo "$opened_bar" > "$PIN_FILE"
    # Zen 会隐藏入口；键盘打开时临时显示锚点，关闭后恢复。
    if [ "$(sketchybar --query "$HOST" | jq -r '.geometry.drawing')" = off ]; then
      touch "$PIN_FILE.host_hidden"
      sketchybar --set "$HOST" drawing=on
    fi
    sketchybar --set "$HOST" popup.drawing=on
    start_spinner $(awk -F'\t' '$2 == "running" { printf "%s.row.%d ", "'"$GROUP"'", NR - 1 }' "$SEQUENCE")
    exit 0
    ;;
  switcher_hide)
    preview_close "$HOST" "$PIN_FILE"
    if [ -f "$PIN_FILE.host_hidden" ]; then
      sketchybar --set "$HOST" drawing=off
      rm -f "$PIN_FILE.host_hidden"
    fi
    exit 0
    ;;
esac

# 以下为悬停事件（切换器进行中时不改行背景，保留选中高亮）
if [[ "$NAME" == "$GROUP".row.* ]] && [ ! -f "$SELECTED" ]; then
  case "$SENDER" in
    mouse.entered) sketchybar --set "$NAME" background.color=$HOVER_BG ;;
    mouse.exited|mouse.exited.global) sketchybar --set "$NAME" background.color=$ROW_BG ;;
  esac
fi

"$PLUGIN_DIR/hover.sh"

hovered() { compgen -G "$HOVER_DIR/$GROUP" >/dev/null || compgen -G "$HOVER_DIR/$GROUP.*" >/dev/null; }

# 悬停只高亮（hover.sh 已处理），不自动弹出；点击打开的面板在鼠标离开后收起
if ! hovered; then
  [ -f "$PIN_FILE" ] && exit 0 # 固定打开的面板不随鼠标收起
  sleep 0.3
  hovered || sketchybar --set "$HOST" popup.drawing=off
fi
