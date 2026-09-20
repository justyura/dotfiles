#!/bin/bash

# 当前 tmux project 的 Things 进度：项目名 + 已完成/总数
# 点击时间轴弹出 Things 3 中与当前 tmux 会话同名项目的待办清单（未完成 + 今天完成；悬停不自动弹出），
# 左键勾选/取消完成、右键在 Things 中打开该待办（things_toggle.sh）；Things 不在运行时不会主动启动它
# alt+k 进入键盘模式操作该清单（things_nav.sh）；day_timeline.sh render 取数据并生成弹窗行

source "$HOME/.config/sketchybar/settings.sh"
source "$HOME/.config/scripts/things/things_lib.sh"

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
HOVER_DIR="$HOME/.cache/sketchybar/hover"

# bar 上的进度用圆环表示（不再显示 x/y 数字），目标是把环走满。
# 图片按「已完成_总数」缓存，缺了才现画（约 23ms）
ring_image() {
  local img="$THINGS_RING_DIR/$1_$2.png"
  [ -f "$img" ] || python3 "$PLUGIN_DIR/progress_ring.py" "$1" "$2" "$img" >/dev/null 2>&1
  printf '%s' "$img"
}

hovered() { compgen -G "$HOVER_DIR/timeline" >/dev/null || compgen -G "$HOVER_DIR/timeline.*" >/dev/null; }

render_things() {
  # 取当前 tmux 会话同名项目的待办写入数据文件，再由 things_nav.sh 生成弹窗行（固定宽度、长任务名折行）
  local project todos status=ok
  things_sync_wait   # 等清单上的勾选/调序先写回 Things，否则这里读到的是旧状态
  project=$(view_project)   # /xxx 跳转过就取那个项目
  if [ -z "$project" ]; then
    status=NO_SESSION
  else
    todos=$(things_list "$project")
    case "$todos" in NOT_RUNNING|NO_PROJECT) status=$todos; todos="" ;; esac
  fi
  mkdir -p "$(dirname "$THINGS_ROWS")"
  printf '%s' "${todos:+$todos$'\n'}" > "$THINGS_ROWS"
  echo "$project" > "$THINGS_PROJECT"
  echo "$status" > "$THINGS_STATUS"
  "$HOME/.config/scripts/things/things_nav.sh" rebuild
}

# refresh：键盘模式打开后在后台取最新数据；取数据期间若用户已操作过清单（行数据文件被改写），放弃本次结果
refresh_things() {
  local project todos status=ok before
  things_sync_wait
  project=$(view_project)
  before=$(stat -f %m "$THINGS_ROWS" 2>/dev/null)
  if [ -z "$project" ]; then
    status=NO_SESSION
  else
    todos=$(things_list "$project")
    case "$todos" in NOT_RUNNING|NO_PROJECT) status=$todos; todos="" ;; esac
  fi
  [ -f "$THINGS_NAV" ] || return 0                                  # 已经关闭
  [ "$(stat -f %m "$THINGS_ROWS" 2>/dev/null)" = "$before" ] || return 0  # 期间有勾选/移动等操作
  local new="${todos:+$todos$'\n'}"
  if [ "$new" = "$(cat "$THINGS_ROWS" 2>/dev/null)"$'\n' ] || { [ -z "$new" ] && [ ! -s "$THINGS_ROWS" ]; }; then
    # 数据没变：只在状态变化（如 Loading… → 空清单提示）时刷新
    [ "$status" = "$(cat "$THINGS_STATUS" 2>/dev/null)" ] && return 0
  fi
  printf '%s' "$new" > "$THINGS_ROWS"
  echo "$project" > "$THINGS_PROJECT"
  echo "$status" > "$THINGS_STATUS"
  "$HOME/.config/scripts/things/things_nav.sh" rebuild
}

if [ "$1" = render ]; then
  render_things
  exit 0
fi
if [ "$1" = refresh ]; then
  refresh_things
  exit 0
fi

case "$SENDER" in
  mouse.clicked)
    # 点击时间轴：打开/关闭 Things 清单（键盘模式 alt+k 打开时不处理）
    [ -f "$THINGS_NAV" ] && exit 0
    if [ "$(sketchybar --query timeline | jq -r '.popup.drawing')" = on ]; then
      sketchybar --set timeline popup.drawing=off
    else
      echo 0 > "$THINGS_SCROLL"
      things_measure_panel
      render_things
      sketchybar --set timeline popup.drawing=on
    fi
    exit 0
    ;;
  mouse.scrolled)
    # 清单弹窗里滚动：交给 things_nav.sh 移动可见区（弹窗固定行数，超出部分靠滚动查看）
    [[ "$NAME" == timeline.things.* ]] && "$HOME/.config/scripts/things/things_nav.sh" scroll "$SCROLL_DELTA"
    exit 0
    ;;
  mouse.entered|mouse.exited|mouse.exited.global)
    # 待办行自身的悬停底色（标题/提示行除外；键盘模式下底色表示光标/选区，不响应悬停）
    # 空行（任务不足一屏时补的占位行）不高亮
    if [[ "$NAME" =~ ^timeline\.things\.line\.[0-9]+$ ]] && [ ! -f "$THINGS_NAV" ] &&
      [ -n "$(sketchybar --query "$NAME" | jq -r '.label.value // empty')" ]; then
      [ "$SENDER" = mouse.entered ] && bg=0xff292e42 || bg=$THINGS_ROW_BG
      sketchybar --set "$NAME" background.color=$bg
    fi
    "$PLUGIN_DIR/hover.sh"
    # 悬停不自动弹出；点击打开的清单在鼠标离开时间轴和清单后收起
    if ! hovered; then
      [ -f "$THINGS_PIN" ] && exit 0 # 键盘模式打开的清单不随鼠标收起
      # 稍等再收起，方便把鼠标移进弹窗点击
      sleep 0.3
      hovered || sketchybar --set timeline popup.drawing=off
    fi
    exit 0
    ;;
esac

[ "$NAME" = timeline ] || exit 0

PROJECT=$(current_project)
if [ -z "$PROJECT" ]; then
  sketchybar --set timeline.project label="No Project" --set timeline background.image="$(ring_image 0 0)"
  exit 0
fi

things_sync_wait
TODOS=$(things_list "$PROJECT")
case "$TODOS" in
  NOT_RUNNING|NO_PROJECT) COMPLETED=0 TOTAL=0 ;;
  "") COMPLETED=0 TOTAL=0 ;;
  *)
    # 已取消的不算数：既不算完成，也不留在总数里（取消 = 这条不做了，环的目标随之变小）
    COMPLETED=$(printf '%s\n' "$TODOS" | awk -F '\t' '$2 == "completed" { n++ } END { print n + 0 }')
    TOTAL=$(printf '%s\n' "$TODOS" | awk -F '\t' 'NF && $2 != "canceled" { n++ } END { print n + 0 }')
    ;;
esac

sketchybar --set timeline.project label="$PROJECT" --set timeline background.image="$(ring_image "$COMPLETED" "$TOTAL")"
