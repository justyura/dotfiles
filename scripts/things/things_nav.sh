#!/bin/bash

# Things 清单弹窗：生成弹窗行 + 键盘模式（skhd 模式 things / thingsv，alt+k 进入；只接管下列按键，其余照常传给当前应用）
#   j/k 上下移动    J/K 调整顺序（写回 Things；参与排序的待办会脱离 heading）
#   alt+k / enter 完成/取消完成（不切换窗口、不关闭清单）    alt+shift+k 标成 canceled（这条不做了）/ 恢复
#   alt+shift+y 把已完成和已取消的归档进 Logbook（作用于全部项目）    o/O 在光标下方/上方插入一行并直接输入（输入期间切到不捕获按键的 thingsinsert 模式）
#   v 可视模式（整段选中，可批量勾选/移动，d 删除，y 复制任务名到剪贴板，一行一条）    esc 可视模式下回到普通模式，普通模式下退出并关闭清单
#   / 项目跳转（skhd 的 thingsjump 模式，按键由 skhd 直接接管，不开输入框）：边打边过滤（fzf 式模糊匹配），
#     弹窗实时显示候选和 n/N 计数，↑↓（或 ctrl-p/ctrl-n）选、回车切过去、esc 取消；
#     回车时 tmux 也切到同名会话（没有会话就按目录新建；本地没有这个工程则只切清单视角）
# 动作：rebuild（day_timeline.sh 取完数据后调用）normal visual leave down up move_down move_up toggle delete yank
#       insert below|above；cancel；archive；jump 系列（/ 键，模糊跳到别的项目）；
#       toggle_id <id>（鼠标左键点击某行，things_toggle.sh 调用）
#       exit_mode（任意清单模式直接回到默认模式）；focus_changed（yabai 焦点/空间变化信号调用）
# 不阻塞键盘：按下清单没用到的打字键立即退出且按键照常输入（skhd/things_passthrough）；
#   窗口/应用/空间切换时自动退出（yabai 信号）；THINGS_NAV_TIMEOUT 秒无操作也自动退出
# 数据/状态文件见 things_lib.sh；弹窗每行固定宽度，任务名过长时折成多行（things_helper wrap）
# 响应速度：勾选/删除/调序都先按乐观结果重绘弹窗（约 10ms），写回 Things 的 AppleScript（约 200ms）
#   排进队列由 things_sync.sh 串行执行，队列清空后再用真实数据刷新 bar 上的进度

export LC_ALL=en_US.UTF-8

# yabai 焦点/空间信号频繁触发：键盘模式没开时直接退出（不加载配置、不写日志）
[ "$1" = focus_changed ] && [ ! -f "$HOME/.cache/sketchybar/things_nav" ] && exit 0

# 动作记录（保留最近 100 条）：排查清单被意外关闭时看是谁触发了哪个动作。
# 每次按键要多花约 28ms（tail/date/ps/cat 五六个进程），所以默认关闭；
# 需要排查时 touch ~/.cache/sketchybar/things_nav_actions.on 打开。
THINGS_ACTION_LOG="$HOME/.cache/sketchybar/things_nav_actions.log"
if [ -f "$THINGS_ACTION_LOG.on" ]; then
  { tail -n 99 "$THINGS_ACTION_LOG" 2>/dev/null
    echo "$(date '+%T') $* sender=${SENDER:-} name=${NAME:-} parent=$(ps -o comm= -p $PPID 2>/dev/null | xargs basename 2>/dev/null) nav=[$(cat "$HOME/.cache/sketchybar/things_nav" 2>/dev/null)]"
  } > "$THINGS_ACTION_LOG.tmp" 2>/dev/null && mv "$THINGS_ACTION_LOG.tmp" "$THINGS_ACTION_LOG"
fi

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
source "$HOME/.config/sketchybar/settings.sh"
source "$HOME/.config/scripts/things/things_lib.sh"
source "$PLUGIN_DIR/preview_lib.sh"

NEW_ID=__new__                                        # 插入中、尚未创建到 Things 的占位行

ids=() states=() names=()
load_rows() {
  ids=() states=() names=()
  local id state name
  while IFS=$'\t' read -r id state name; do
    [ -n "$id" ] || continue
    ids+=("$id") states+=("$state") names+=("$name")
  done < "$THINGS_ROWS" 2>/dev/null
}

write_rows() {
  local i
  for i in "${!ids[@]}"; do
    [ "${ids[$i]}" = "$NEW_ID" ] && continue
    printf '%s\t%s\t%s\n' "${ids[$i]}" "${states[$i]}" "${names[$i]}"
  done > "$THINGS_ROWS.tmp"
  mv "$THINGS_ROWS.tmp" "$THINGS_ROWS"
}

cursor=-1 anchor=-1
load_nav() { [ -f "$THINGS_NAV" ] && read -r cursor anchor < "$THINGS_NAV"; }
save_nav() { echo "$cursor $anchor" > "$THINGS_NAV"; }

# 任意清单模式（普通/可视/输入中）直接回到 skhd 默认模式（things,thingsv,thingsinsert < f19 ; default → leave）
exit_mode() {
  pkill -f "^$THINGS_HELPER input" 2>/dev/null   # 锚定到二进制绝对路径，避免误杀命令行里恰好含这串的进程
  skhd -k "f19"
}

# 超时守护：键盘模式期间每 2 秒检查一次，THINGS_NAV_TIMEOUT 秒内没有任何清单操作（状态文件未更新）就退出
start_watchdog() {
  (
    while sleep 2; do
      [ -f "$THINGS_NAV" ] || exit 0
      [ -f "$THINGS_INSERTING" ] && continue
      idle=$(( $(date +%s) - $(stat -f %m "$THINGS_NAV") ))
      if [ "$idle" -ge "${THINGS_NAV_TIMEOUT:-30}" ]; then exit_mode; exit 0; fi
    done
  ) >/dev/null 2>&1 &
}

# 选区 [lo, hi]：可视模式为 anchor..cursor，否则只有光标行
range() {
  if [ "$anchor" -ge 0 ]; then
    lo=$((anchor < cursor ? anchor : cursor)) hi=$((anchor > cursor ? anchor : cursor))
  else
    lo=$cursor hi=$cursor
  fi
}

row_bg() {
  if [ "$cursor" -ge 0 ]; then
    [ "$1" -eq "$cursor" ] && { echo $THINGS_CURSOR_BG; return; }
    [ "$anchor" -ge 0 ] && [ "$1" -ge "$lo" ] && [ "$1" -le "$hi" ] && { echo $THINGS_SELECT_BG; return; }
  fi
  echo $THINGS_ROW_BG
}

# 滚动：弹窗固定 THINGS_PANEL_LINES 个行条目（timeline.things.line.0..N-1，按可见位置命名），
# 显示折行后第 top 行开始的一段。THINGS_MAP 记录每个任务在「全部折行」里的绝对位置："行号 起始line 行数"。
THINGS_MAP="$HOME/.cache/sketchybar/things_rows_map"

# 调整 top 让光标所在任务完整可见（上下留 THINGS_SCROLLOFF 行），并收拢到有效范围；top 变了返回 0
ensure_visible() {
  local old i s c start="" cnt="" total=0 max lines=$THINGS_PANEL_LINES so=$THINGS_SCROLLOFF
  read -r top 2>/dev/null < "$THINGS_SCROLL"
  [[ "$top" =~ ^[0-9]+$ ]] || top=0
  old=$top
  while read -r i s c; do
    total=$((s + c))
    [ "$i" = "$cursor" ] && start=$s cnt=$c
  done < "$THINGS_MAP"
  if [ -n "$start" ]; then
    [ $((start - so)) -lt "$top" ] && top=$((start - so))
    [ $((start + cnt + so)) -gt $((top + lines)) ] && top=$((start + cnt + so - lines))
  fi
  max=$((total - lines)); [ "$max" -lt 0 ] && max=0
  [ "$top" -gt "$max" ] && top=$max
  [ "$top" -lt 0 ] && top=0
  echo "$top" > "$THINGS_SCROLL"
  [ "$top" != "$old" ]
}

# 按内存中的行数据刷新弹窗条目，避免闪烁：条目数量固定（标题 + N 行 + 底栏），平时只原地 --set；
# 结构不对（首次打开、旧格式）时才整体重建。
rebuild() {
  local args=() item i k s c seg project status message label
  local existing=() cur_lines=0 has_header=0 has_footer=0 other=0 V=$THINGS_PANEL_LINES
  while read -r item; do
    [ -n "$item" ] || continue
    existing+=("$item")
    case "$item" in
      timeline.things.header) has_header=1 ;;
      timeline.things.footer) has_footer=1 ;;
      timeline.things.line.*) cur_lines=$((cur_lines + 1)) ;;
      *) other=1 ;;
    esac
  done < <(sketchybar --query timeline | jq -r '.popup.items[]?')

  if [ "$has_header" -eq 0 ] || [ "$has_footer" -eq 0 ] || [ "$other" -eq 1 ] || [ "$cur_lines" -ne "$V" ]; then
    for item in "${existing[@]}"; do args+=(--remove "$item"); done
    args+=(--add item timeline.things.header popup.timeline
      --subscribe timeline.things.header mouse.entered mouse.exited mouse.scrolled)
    for ((k = 0; k < V; k++)); do
      args+=(--add item "timeline.things.line.$k" popup.timeline
        --subscribe "timeline.things.line.$k" mouse.entered mouse.exited mouse.scrolled)
    done
    args+=(--add item timeline.things.footer popup.timeline
      --subscribe timeline.things.footer mouse.entered mouse.exited mouse.scrolled)
  fi

  project=$(cat "$THINGS_PROJECT" 2>/dev/null)
  status=$(cat "$THINGS_STATUS" 2>/dev/null)
  args+=(--set timeline.things.header width=$THINGS_WIDTH icon.drawing=off label="Things · ${project:-no tmux session}"
      label.font="SF Pro:Semibold:14.0" label.color=$THINGS_HEADER label.padding_left=16
      background.drawing=off background.height=40 script="$PLUGIN_DIR/day_timeline.sh")

  message=""
  case "$status" in
    NOT_RUNNING) message="Things 3 is not running" ;;
    NO_PROJECT) message="No Things project named \"$project\"" ;;
    NO_SESSION) message="No tmux session" ;;
    LOADING) message="Loading…" ;;
    *) [ ${#ids[@]} -eq 0 ] && message="No to-dos — press o to add one" ;;
  esac

  # 全部任务折行后的各段
  local want_text=() want_row=() lines=() segs_arr=()
  if [ ${#ids[@]} -gt 0 ]; then
    while IFS= read -r seg; do lines+=("$seg"); done < <(
      printf '%s\n' "${names[@]}" | things_wrap "$THINGS_TEXT_WIDTH" "$THINGS_FONT_SIZE"
    )
  fi
  : > "$THINGS_MAP"
  for i in "${!ids[@]}"; do
    IFS=$'\x1f' read -r -a segs_arr <<< "${lines[$i]:-${names[$i]}}"
    [ ${#segs_arr[@]} -eq 0 ] && segs_arr=("")
    echo "$i ${#want_text[@]} ${#segs_arr[@]}" >> "$THINGS_MAP"
    k=0
    for seg in "${segs_arr[@]}"; do want_text+=("$seg"); want_row+=("$i:$k"); k=$((k + 1)); done
  done
  local n=${#want_text[@]}
  ensure_visible

  # 可见区：第 top..top+V-1 段画进 line.0..line.V-1，不足的留空（保持定高）
  range
  local abs r row_k bg icon_args color click
  for ((k = 0; k < V; k++)); do
    abs=$((top + k))
    if [ "$abs" -ge "$n" ]; then
      label=""
      [ "$k" -eq 0 ] && [ "$n" -eq 0 ] && label=$message
      args+=(--set "timeline.things.line.$k" width=$THINGS_WIDTH icon.drawing=off
        label="$label" label.color=$THINGS_HEADER label.font="SF Pro:Medium:${THINGS_FONT_SIZE}.0"
        label.padding_left=$THINGS_INDENT label.padding_right=0
        background.color=$THINGS_ROW_BG background.corner_radius=6 background.height=$THINGS_LINE_HEIGHT
        background.padding_left=8 background.padding_right=8
        click_script="" script="$PLUGIN_DIR/day_timeline.sh")
      continue
    fi
    r=${want_row[$abs]%%:*} row_k=${want_row[$abs]##*:}
    bg=$(row_bg "$r")
    case "${states[$r]}" in completed|canceled) color=$THINGS_DONE_TEXT ;; *) color=$THINGS_TEXT ;; esac
    if [ "$row_k" -eq 0 ]; then
      case "${states[$r]}" in
        completed) icon_args=(icon.drawing=on icon="$THINGS_BOX_DONE" icon.color=$THINGS_BOX_DONE_COLOR label.padding_left=0) ;;
        canceled)  icon_args=(icon.drawing=on icon="$THINGS_BOX_CANCELED" icon.color=$THINGS_BOX_CANCELED_COLOR label.padding_left=0) ;;
        *)         icon_args=(icon.drawing=on icon="$THINGS_BOX_OPEN" icon.color=$THINGS_BOX_COLOR label.padding_left=0) ;;
      esac
    else
      icon_args=(icon.drawing=off label.padding_left=$THINGS_INDENT)
    fi
    click=""
    [ "${ids[$r]}" != "$NEW_ID" ] && click="$HOME/.config/scripts/things/things_toggle.sh ${ids[$r]}"
    args+=(--set "timeline.things.line.$k" width=$THINGS_WIDTH "${icon_args[@]}"
      icon.font="Hack Nerd Font:Regular:18.0" icon.padding_left=12 icon.padding_right=10
      label="${want_text[$abs]}" label.color=$color label.font="SF Pro:Medium:${THINGS_FONT_SIZE}.0" label.padding_right=0
      background.color=$bg background.corner_radius=6 background.height=$THINGS_LINE_HEIGHT
      background.padding_left=8 background.padding_right=8
      click_script="$click" script="$PLUGIN_DIR/day_timeline.sh")
  done

  # 底栏：总数 / 已完成；超出可见区时显示上下各还有几条没露出来
  local done_n=0 above=0 below=0 footer=""
  for s in "${states[@]}"; do [ "$s" = completed ] && done_n=$((done_n + 1)); done
  while read -r i s c; do
    [ $((s + c)) -le "$top" ] && above=$((above + 1))
    [ "$s" -ge $((top + V)) ] && below=$((below + 1))
  done < "$THINGS_MAP"
  [ ${#ids[@]} -gt 0 ] && footer="${#ids[@]} 条 · 已完成 $done_n"
  [ $((above + below)) -gt 0 ] && footer="$footer      ↑ $above   ↓ $below"
  args+=(--set timeline.things.footer width=$THINGS_WIDTH icon.drawing=off label="$footer"
      label.font="SF Pro:Medium:11.0" label.color=0xff737aa2 label.padding_left=16
      background.drawing=off background.height=32 script="$PLUGIN_DIR/day_timeline.sh")

  # 键盘模式期间始终保持清单显示（兜底：任何情况下刷新都不让面板被收起）
  [ -f "$THINGS_NAV" ] && args+=(--set timeline popup.drawing=on)
  sketchybar "${args[@]}"
}

# 只更新背景色（光标移动、进出可视模式）；光标移出可见区时滚动并整体重绘
paint_bg() {
  local args=() i start n k bg
  if ensure_visible; then
    [ ${#ids[@]} -gt 0 ] || load_rows
    rebuild
    return
  fi
  range
  while read -r i start n; do
    bg=$(row_bg "$i")
    for ((k = start; k < start + n; k++)); do
      [ "$k" -ge "$top" ] && [ "$k" -lt $((top + THINGS_PANEL_LINES)) ] || continue
      args+=(--set "timeline.things.line.$((k - top))" background.color=$bg)
    done
  done < "$THINGS_MAP"
  [ ${#args[@]} -gt 0 ] && sketchybar "${args[@]}"
}

refresh_first() { NAME=timeline SENDER=routine "$PLUGIN_DIR/day_timeline.sh" >/dev/null 2>&1 & }

# ===== / 跳转时的候选列表 =====
# 复用弹窗里的 timeline.things.line.N：过滤期间它们显示项目名，结束后 rebuild 会还原成待办
JUMP_MAX=$THINGS_PANEL_LINES    # 候选和待办共用固定行数的面板（再多就滚动）
jump_rows=0    # 一次跳转期间固定的行数：过滤到几个候选都画这么多行（不足补空行），
               # 否则弹窗高度会随候选数变化，居中展开的面板会上下乱飘，绝对定位的输入框还会对不齐

jump_filter() {  # $1=查询；空查询给全部候选（不动 sel，由调用方决定）
  matches=()
  if [ -z "$1" ]; then
    matches=("${projects[@]}")
  else
    while IFS= read -r line; do [ -n "$line" ] && matches+=("$line"); done < <(
      printf '%s\n' "${projects[@]}" | things_fuzzy "$1")
  fi
}

jump_load_projects() {
  projects=()
  while IFS= read -r line; do [ -n "$line" ] && projects+=("$line"); done < "$THINGS_PROJECTS_CACHE" 2>/dev/null
}

# 跳转状态要跨进程（每个按键都是 skhd 新起的一次调用）："光标 行数 原行数 有无提示行"
jump_state_load() {
  sel=0 jump_rows=0 jump_lines=0 jump_msg=0
  [ -f "$THINGS_JUMP_STATE" ] && read -r sel jump_rows jump_lines jump_msg < "$THINGS_JUMP_STATE"
  return 0
}

jump_state_save() {
  printf '%s %s %s %s\n' "$sel" "$jump_rows" "$jump_lines" "$jump_msg" > "$THINGS_JUMP_STATE"
}

# 查询串不存进状态文件：按键一个一个来、每个都是独立进程，读-改-写会互相覆盖（连打会丢字符）。
# 改成只往日志里追加 token（短行追加是原子的，顺序天然有保证），查询串由回放得出。
jump_query() {
  local q="" tok
  while IFS= read -r tok; do
    case "$tok" in
      BS) q=${q%?} ;;
      SP) q="$q " ;;
      *)  q="$q$tok" ;;
    esac
  done < "$THINGS_JUMP_KEYS" 2>/dev/null
  printf '%s' "$q"
}

jump_render() {
  local args=() n=${#matches[@]} start k i bg color label
  start=0
  [ "$sel" -ge "$jump_rows" ] && start=$((sel - jump_rows + 1))   # 选中项滚进可见范围
  args+=(--set timeline.things.header label="跳转到项目 › ${query}▏ · $([ "$n" -eq 0 ] && echo 0 || echo $((sel + 1)))/$n")
  args+=(--set timeline.things.footer label="↑↓ 选择 · ⏎ 切换 · esc 取消")
  if [ "$jump_msg" -eq 1 ]; then args+=(--remove timeline.things.msg); jump_msg=0; fi
  # 行数只在进入跳转时对齐一次，之后固定：弹窗高度不变，面板和输入框都不会动
  for ((k = jump_rows; k < jump_lines; k++)); do args+=(--remove "timeline.things.line.$k"); done
  for ((k = jump_lines; k < jump_rows; k++)); do
    args+=(--add item "timeline.things.line.$k" popup.timeline
      --subscribe "timeline.things.line.$k" mouse.entered mouse.exited)
  done
  jump_lines=$jump_rows
  for ((k = 0; k < jump_rows; k++)); do
    i=$((start + k))
    if [ "$i" -lt "$n" ]; then label=${matches[$i]}; else label=""; fi   # 不足的行留空，保持定高
    if [ "$i" -eq "$sel" ] && [ "$i" -lt "$n" ]; then
      bg=$THINGS_CURSOR_BG color=$THINGS_TEXT
    else
      bg=$THINGS_ROW_BG color=$THINGS_DONE_TEXT
    fi
    args+=(--set "timeline.things.line.$k" width=$THINGS_WIDTH icon.drawing=off
      label="$label" label.color=$color label.font="SF Pro:Medium:${THINGS_FONT_SIZE}.0"
      label.padding_left=$THINGS_INDENT label.padding_right=0
      background.color=$bg background.corner_radius=4 background.height=$THINGS_LINE_HEIGHT
      click_script="" script="")
  done
  sketchybar "${args[@]}"
}

# 未完成的行排在前面，数出它们的个数（只有这些行可以调整顺序）
count_open() {
  nopen=0
  local s
  for s in "${states[@]}"; do [ "$s" = open ] && nopen=$((nopen + 1)) || break; done
}

# 把前 nopen 行的顺序写回 Things（排进队列，由 things_sync.sh 在后台落地）
push_order() {
  local csv
  csv=$(IFS=,; echo "${ids[*]:0:$nopen}")
  [ -n "$csv" ] && things_enqueue order "$(cat "$THINGS_PROJECT")" "$csv"
}

# 任何按键动作都算一次操作，刷新状态文件时间（供超时守护判断）
case "$1" in
  down|up|scroll|toggle|cancel|archive|delete|yank|move_down|move_up|insert|visual|jump|jumpkey|jumpmove) [ -f "$THINGS_NAV" ] && touch "$THINGS_NAV" ;;
esac

case "$1" in
  exit_mode)
    [ -f "$THINGS_NAV" ] && exit_mode
    ;;

  focus_changed)
    # yabai 信号：真正切换到别的窗口/空间时退出键盘模式。
    # 只比对「聚焦窗口 id + 空间号」是否和进入模式时不同，避免输入法状态提示（按 Shift 切中英文）等
    # 不抢焦点的窗口触发误退出；o/O 输入框自身抢焦点及结束后的焦点回退也忽略
    [ -f "$THINGS_NAV" ] || exit 0
    now_focus="$(/opt/homebrew/bin/yabai -m query --windows --window 2>/dev/null | jq -r '.id // "-"') $(/opt/homebrew/bin/yabai -m query --spaces --space 2>/dev/null | jq -r '.index // "-"')"
    if [ -f "$THINGS_INSERTING" ]; then decision="ignore(inserting)"
    elif [ "$now_focus" = "$(cat "$THINGS_FOCUS" 2>/dev/null)" ]; then decision="ignore(same focus)"
    else decision=exit; fi
    { tail -n 49 "$THINGS_FOCUS_LOG" 2>/dev/null
      echo "$(date '+%F %T') ${YABAI_EVENT_TYPE:-signal} pid=${YABAI_PROCESS_ID:-} win=${YABAI_WINDOW_ID:-} focus=[$now_focus] base=[$(cat "$THINGS_FOCUS" 2>/dev/null)] -> $decision"
    } > "$THINGS_FOCUS_LOG.tmp" && mv "$THINGS_FOCUS_LOG.tmp" "$THINGS_FOCUS_LOG"
    [ "$decision" = exit ] && exit_mode
    ;;

  rebuild)
    load_rows; load_nav
    if [ -f "$THINGS_NAV" ]; then
      # 后台刷新后行数可能变少：光标和选区收拢到有效范围
      [ "$cursor" -ge ${#ids[@]} ] && cursor=$((${#ids[@]} - 1))
      [ ${#ids[@]} -gt 0 ] && [ "$cursor" -lt 0 ] && cursor=0
      [ "$anchor" -ge ${#ids[@]} ] && anchor=$((${#ids[@]} - 1))
      save_nav
    else
      cursor=-1
    fi
    rebuild
    ;;

  normal)
    if [ -f "$THINGS_NAV" ]; then
      # 从可视模式 / 输入模式回到普通模式（save_nav 同时刷新超时计时）
      load_nav; anchor=-1; save_nav; paint_bg
      exit 0
    fi
    # 打开清单：先用缓存立即弹出，再在后台从 Things 取最新数据原地刷新（读 Things 约 0.5s）
    mkdir -p "$(dirname "$THINGS_PIN")"
    opened_bar=0
    if [ -f "$BAR_HIDDEN_FILE" ]; then
      # bar 隐藏时顺带显示（不等它完成）
      "$TOGGLE_BAR" >/dev/null 2>&1 &
      opened_bar=1
    fi
    echo "$opened_bar" > "$THINGS_PIN"
    # 记下进入模式时的聚焦窗口和空间，供 focus_changed 判断是否真的切走了
    ( echo "$(/opt/homebrew/bin/yabai -m query --windows --window 2>/dev/null | jq -r '.id // "-"') $(/opt/homebrew/bin/yabai -m query --spaces --space 2>/dev/null | jq -r '.index // "-"')" > "$THINGS_FOCUS" ) &
    echo "0 -1" > "$THINGS_NAV"
    echo 0 > "$THINGS_SCROLL"
    things_measure_panel

    project=$(view_project)
    if [ -z "$project" ] || [ "$project" != "$(cat "$THINGS_PROJECT" 2>/dev/null)" ]; then
      # 缓存不是这个项目的：先显示标题 + Loading…
      : > "$THINGS_ROWS"
      echo "$project" > "$THINGS_PROJECT"
      echo LOADING > "$THINGS_STATUS"
    fi
    load_rows; load_nav
    [ ${#ids[@]} -eq 0 ] && cursor=-1 && save_nav
    rebuild
    sketchybar --set timeline popup.drawing=on
    start_watchdog
    "$PLUGIN_DIR/day_timeline.sh" refresh >/dev/null 2>&1 &
    ;;

  visual)
    load_nav
    [ "$cursor" -ge 0 ] && anchor=$cursor
    save_nav; paint_bg
    ;;

  leave)
    [ -f "$THINGS_NAV" ] || exit 0
    rm -f "$THINGS_NAV" "$THINGS_VIEW" "$THINGS_JUMP_STATE" "$THINGS_JUMP_KEYS"
    cursor=-1; paint_bg
    preview_close timeline "$THINGS_PIN"
    ;;

  down|up)
    load_nav; load_rows
    [ ${#ids[@]} -gt 0 ] || exit 0
    [ "$1" = down ] && cursor=$((cursor + 1)) || cursor=$((cursor - 1))
    [ "$cursor" -lt 0 ] && cursor=0
    [ "$cursor" -ge ${#ids[@]} ] && cursor=$((${#ids[@]} - 1))
    save_nav; paint_bg
    ;;

  toggle)
    load_nav; load_rows
    [ "$cursor" -ge 0 ] || exit 0
    range
    # 与 Things 多选勾选一致：选区里有未完成的就全部完成，否则全部取消完成
    target=open
    for i in $(seq "$lo" "$hi"); do [ "${states[$i]}" = open ] && target=completed; done
    sel=()
    for i in $(seq "$lo" "$hi"); do sel+=("${ids[$i]}"); states[$i]=$target; done
    # 先按乐观结果渲染，再排队写回 Things（bar 上的进度由 things_sync.sh 在队列清空后刷新）
    write_rows; rebuild
    things_enqueue status "$target" "${sel[*]}"
    # 可视模式下操作完回到普通模式（skhd: thingsv < escape ; things → normal）
    [ "$anchor" -ge 0 ] && skhd -k "escape"
    ;;

  cancel)
    # alt+shift+k：把选中的待办标成 canceled（这条不做了），全都已取消时再按一次恢复成未完成
    load_nav; load_rows
    [ "$cursor" -ge 0 ] || exit 0
    range
    target=open
    for i in $(seq "$lo" "$hi"); do [ "${states[$i]}" = canceled ] || target=canceled; done
    sel=()
    for i in $(seq "$lo" "$hi"); do sel+=("${ids[$i]}"); states[$i]=$target; done
    # 先按乐观结果渲染，再排队写回 Things
    write_rows; rebuild
    things_enqueue status "$target" "${sel[*]}"
    # 可视模式下操作完回到普通模式
    [ "$anchor" -ge 0 ] && skhd -k "escape"
    ;;

  archive)
    # alt+shift+y：把已完成/已取消的待办归档进 Logbook（Things 的 "Log completed items now"，作用于全部项目）
    load_nav; load_rows
    n_ids=() n_states=() n_names=()
    for i in "${!ids[@]}"; do
      [ "${states[$i]}" = open ] || continue
      n_ids+=("${ids[$i]}") n_states+=("${states[$i]}") n_names+=("${names[$i]}")
    done
    ids=("${n_ids[@]}") states=("${n_states[@]}") names=("${n_names[@]}")
    [ "$cursor" -ge ${#ids[@]} ] && cursor=$((${#ids[@]} - 1))
    anchor=-1
    write_rows; save_nav; rebuild
    things_enqueue archive
    ;;

  toggle_id)
    load_nav; load_rows
    for i in "${!ids[@]}"; do
      if [ "${ids[$i]}" = "$2" ]; then
        [ "${states[$i]}" = open ] && states[$i]=completed || states[$i]=open
        write_rows; rebuild
        things_enqueue status "${states[$i]}" "$2"
        break
      fi
    done
    ;;

  delete)
    load_nav; load_rows
    [ "$cursor" -ge 0 ] || exit 0
    range
    sel=("${ids[@]:$lo:$((hi - lo + 1))}")
    ids=("${ids[@]:0:$lo}" "${ids[@]:$((hi + 1))}")
    states=("${states[@]:0:$lo}" "${states[@]:$((hi + 1))}")
    names=("${names[@]:0:$lo}" "${names[@]:$((hi + 1))}")
    cursor=$lo
    [ "$cursor" -ge ${#ids[@]} ] && cursor=$((${#ids[@]} - 1))
    was_visual=$anchor
    anchor=-1
    write_rows; save_nav; rebuild
    things_enqueue delete "${sel[*]}"
    [ "$was_visual" -ge 0 ] && skhd -k "escape"
    ;;

  scroll)
    # 鼠标滚轮 / 触控板（day_timeline.sh 转发 mouse.scrolled）：$2 = SCROLL_DELTA，负数往下，每格 3 行
    [ -f "$THINGS_JUMP_STATE" ] && exit 0            # / 跳转候选期间不滚
    delta=${2:-0}
    [[ "$delta" =~ ^-?[0-9]+$ ]] && [ "$delta" -ne 0 ] || exit 0
    load_nav; load_rows
    [ -f "$THINGS_NAV" ] || cursor=-1
    V=$THINGS_PANEL_LINES so=$THINGS_SCROLLOFF
    read -r top 2>/dev/null < "$THINGS_SCROLL"; [[ "$top" =~ ^[0-9]+$ ]] || top=0
    total=$(awk 'END { print $2 + $3 }' "$THINGS_MAP" 2>/dev/null); [[ "$total" =~ ^[0-9]+$ ]] || total=0
    max=$((total - V)); [ "$max" -lt 0 ] && max=0
    old_top=$top
    [ "$delta" -lt 0 ] && top=$((top + 3)) || top=$((top - 3))
    [ "$top" -gt "$max" ] && top=$max
    [ "$top" -lt 0 ] && top=0
    [ "$top" = "$old_top" ] && exit 0
    echo "$top" > "$THINGS_SCROLL"
    if [ "$cursor" -ge 0 ]; then
      # 光标跟着留在可见区（留出 scrolloff，否则 rebuild 会把视图拉回光标处）
      lo_line=$top; [ "$top" -gt 0 ] && lo_line=$((top + so))
      hi_line=$((top + V)); [ "$top" -lt "$max" ] && hi_line=$((top + V - so))
      first="" last="" cs="" cc=0
      while read -r i s c; do
        [ "$i" = "$cursor" ] && cs=$s cc=$c
        [ -z "$first" ] && [ "$s" -ge "$lo_line" ] && first=$i
        [ $((s + c)) -le "$hi_line" ] && last=$i
      done < "$THINGS_MAP"
      if [ -z "$cs" ]; then :
      elif [ "$cs" -lt "$lo_line" ] && [ -n "$first" ]; then cursor=$first
      elif [ $((cs + cc)) -gt "$hi_line" ] && [ -n "$last" ]; then cursor=$last; fi
      save_nav
    fi
    rebuild
    ;;

  yank)
    # 可视模式 y：选区内的任务名一行一条写进剪贴板（插入中的占位行跳过），然后回到普通模式
    load_nav; load_rows
    [ "$cursor" -ge 0 ] || exit 0
    range
    text=""
    for i in $(seq "$lo" "$hi"); do
      [ "${ids[$i]}" = "$NEW_ID" ] || text+="${names[$i]}"$'\n'
    done
    printf '%s' "${text%$'\n'}" | pbcopy
    read -r top 2>/dev/null < "$THINGS_SCROLL"; [[ "$top" =~ ^[0-9]+$ ]] || top=0
    # 像 nvim 的 vim.hl.on_yank：被复制的行橙底深字闪 150ms，再按原样重绘（rebuild 会恢复文字/勾选框颜色）
    flash=()
    while read -r i start count; do
      [ "$i" -ge "$lo" ] && [ "$i" -le "$hi" ] || continue
      for ((k = start; k < start + count; k++)); do
        [ "$k" -ge "$top" ] && [ "$k" -lt $((top + THINGS_PANEL_LINES)) ] || continue
        flash+=(--set "timeline.things.line.$((k - top))" background.color=$THINGS_YANK_BG label.color=$THINGS_YANK_TEXT icon.color=$THINGS_YANK_TEXT)
      done
    done < "$THINGS_MAP"
    [ ${#flash[@]} -gt 0 ] && sketchybar "${flash[@]}" && sleep 0.15
    anchor=-1; save_nav; rebuild
    # thingsv < escape ; things → normal 回到普通模式
    skhd -k "escape"
    ;;

  move_down|move_up)
    load_nav; load_rows
    [ "$cursor" -ge 0 ] || exit 0
    range; count_open
    [ "$hi" -lt "$nopen" ] || exit 0  # 选区含已完成的行，不能移动
    if [ "$1" = move_up ]; then
      [ "$lo" -gt 0 ] || exit 0
      other=$((lo - 1)) dest=$hi step=-1
    else
      [ $((hi + 1)) -lt "$nopen" ] || exit 0
      other=$((hi + 1)) dest=$lo step=1
    fi
    # 把相邻的那一行挪到选区另一侧，选区整体移动一格
    o_id=${ids[$other]} o_state=${states[$other]} o_name=${names[$other]}
    if [ "$step" -eq -1 ]; then
      for ((i = lo - 1; i < hi; i++)); do ids[$i]=${ids[$((i + 1))]} states[$i]=${states[$((i + 1))]} names[$i]=${names[$((i + 1))]}; done
    else
      for ((i = hi + 1; i > lo; i--)); do ids[$i]=${ids[$((i - 1))]} states[$i]=${states[$((i - 1))]} names[$i]=${names[$((i - 1))]}; done
    fi
    ids[$dest]=$o_id states[$dest]=$o_state names[$dest]=$o_name
    cursor=$((cursor + step))
    [ "$anchor" -ge 0 ] && anchor=$((anchor + step))
    write_rows; save_nav; rebuild
    push_order
    ;;

  jump)
    # 进入 / 跳转模式（skhd 的 :: thingsjump 调用）：按键由 skhd 直接接管，不开输入框
    [ -f "$THINGS_NAV" ] || { skhd -k "f17"; exit 0; }
    jump_load_projects
    # 候选走缓存（读 Things 要 300ms+），同时后台刷新一份给下次用
    ( things_projects > "$THINGS_PROJECTS_CACHE.tmp" 2>/dev/null &&
      mv "$THINGS_PROJECTS_CACHE.tmp" "$THINGS_PROJECTS_CACHE" ) &
    read -r jump_lines jump_msg <<< "$(sketchybar --query timeline | jq -r '.popup.items? // [] |
      ([.[] | select(startswith("timeline.things.line."))] | length),
      ([.[] | select(. == "timeline.things.msg")] | length)' | tr '\n' ' ')"
    # 行数固定为面板行数：弹窗高度不随候选数变化，居中展开的面板不会上下乱飘
    jump_rows=$JUMP_MAX
    sel=0 query=""
    : > "$THINGS_JUMP_KEYS"
    matches=("${projects[@]}")
    jump_render
    jump_lines=$jump_rows jump_msg=0
    jump_state_save
    ;;

  jumpkey)
    # $2: 单个字符，或 BS(退格) / SP(空格)
    printf '%s\n' "$2" >> "$THINGS_JUMP_KEYS"
    jump_state_load; jump_load_projects
    while :; do
      n_before=$(wc -c < "$THINGS_JUMP_KEYS" 2>/dev/null)
      query=$(jump_query)
      jump_filter "$query"; sel=0
      jump_render
      # 渲染期间又按了键：再渲染一次，保证画面是最新的查询串
      [ "$(wc -c < "$THINGS_JUMP_KEYS" 2>/dev/null)" = "$n_before" ] && break
    done
    jump_state_save
    ;;

  jumpmove)
    jump_state_load; jump_load_projects; query=$(jump_query); jump_filter "$query"
    case "$2" in
      down) [ $((sel + 1)) -lt ${#matches[@]} ] && sel=$((sel + 1)) ;;
      up)   [ "$sel" -gt 0 ] && sel=$((sel - 1)) ;;
    esac
    jump_render; jump_state_save
    ;;

  jumpaccept|jumpcancel)
    jump_state_load; jump_load_projects; query=$(jump_query); jump_filter "$query"
    target=""
    [ "$1" = jumpaccept ] && [ ${#matches[@]} -gt 0 ] && target=${matches[$sel]}
    rm -f "$THINGS_JUMP_STATE" "$THINGS_JUMP_KEYS"
    load_rows; load_nav
    if [ -f "$THINGS_NAV" ] && [ -n "$target" ] && [ "$target" != "$(cat "$THINGS_PROJECT" 2>/dev/null)" ]; then
      # tmux 也跟着跳到同名会话（已经在上面就不动，没有会话就按目录新建）；
      # 切成功后清单和 bar 都跟着 tmux 走，不需要视角覆盖，切不过去（本地没有这个工程）才只切清单视角
      if things_switch_session "$target"; then
        rm -f "$THINGS_VIEW"
      else
        echo "$target" > "$THINGS_VIEW"
      fi
      echo "0 -1" > "$THINGS_NAV"                      # 光标回到第一条
      echo 0 > "$THINGS_SCROLL"
      : > "$THINGS_ROWS"                               # 先清空显示 Loading…，取数据约 0.4s
      echo "$target" > "$THINGS_PROJECT"
      echo LOADING > "$THINGS_STATUS"
      load_rows; load_nav; rebuild
      "$PLUGIN_DIR/day_timeline.sh" render >/dev/null 2>&1
      refresh_first                                    # bar 上的项目名和进度也跟着变
    else
      rebuild    # 取消/没选中：把候选行还原成待办、标题行还原成项目名
    fi
    skhd -k "f17"  # thingsjump < f17 ; things
    ;;

  insert)
    load_nav; load_rows; count_open
    if [ ${#ids[@]} -eq 0 ] || [ "$cursor" -lt 0 ]; then pos=0
    elif [ "$2" = above ]; then pos=$cursor
    else pos=$((cursor + 1)); fi
    [ "$pos" -gt "$nopen" ] && pos=$nopen  # 新任务是未完成的，只能放在未完成的行之间

    # 插入占位行并重建，光标移到占位行
    ids=("${ids[@]:0:$pos}" "$NEW_ID" "${ids[@]:$pos}")
    states=("${states[@]:0:$pos}" open "${states[@]:$pos}")
    names=("${names[@]:0:$pos}" "" "${names[@]:$pos}")
    cursor=$pos anchor=-1
    save_nav; rebuild

    # 输入期间切到 thingsinsert 模式（不绑定清单按键），键盘交给输入框（支持输入法）
    touch "$THINGS_INSERTING"
    skhd -k "f18"
    sleep 0.05

    # 输入框盖在占位行上；每存一条清单就多一行、占位行往下挪，所以坐标要重算后推给它
    box_rect() {
      local start r
      start=$(awk -v r="$pos" '$1 == r {print $2}' "$THINGS_MAP")
      r=$(sketchybar --query "timeline.things.line.$(( ${start:-0} - top ))" |
        jq -r '.bounding_rects | to_entries[0].value | "\(.origin[0]) \(.origin[1]) \(.size[0]) \(.size[1])"')
      read -r rx ry rw rh <<< "$r"
      printf '%s %s %s %s' "$(echo "$rx + $THINGS_INDENT" | bc)" "$ry" \
        "$(echo "$rw - $THINGS_INDENT - 12" | bc)" "$rh"
    }

    # --multi：回车存一条后输入框不关，接着录下一条；空回车或 esc 才结束
    read -r bx by bw bh <<< "$(box_rect)"
    fifo="$HOME/.cache/sketchybar/things_insert_fifo.$$"
    mkfifo "$fifo" 2>/dev/null
    exec 3< <(things_helper input "$bx" "$by" "$bw" "$bh" "$THINGS_FONT_SIZE" --multi < "$fifo")
    exec 4> "$fifo"      # 写端一直开着，否则 helper 立刻读到 EOF
    rm -f "$fifo"        # 两端都已打开，路径可以删了

    while IFS= read -r text <&3; do
      text=$(printf '%s' "$text" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
      [ -n "$text" ] || break                        # 空回车：录完了
      [ -f "$THINGS_NAV" ] || break                  # 期间退出了键盘模式（切窗口/超时）
      new_id=$(things_create "$(cat "$THINGS_PROJECT")" "$text")
      [ -n "$new_id" ] || break
      ids[$pos]=$new_id names[$pos]=$text
      nopen=$((nopen + 1))
      push_order
      # 下面再插一个占位行，继续录下一条
      pos=$((pos + 1))
      ids=("${ids[@]:0:$pos}" "$NEW_ID" "${ids[@]:$pos}")
      states=("${states[@]:0:$pos}" open "${states[@]:$pos}")
      names=("${names[@]:0:$pos}" "" "${names[@]:$pos}")
      cursor=$pos
      write_rows; save_nav; rebuild
      read -r bx by bw bh <<< "$(box_rect)"
      echo "rect $bx $by $bw $bh" >&4
    done
    exec 3<&- 4>&-
    pkill -f "^$THINGS_HELPER input" 2>/dev/null     # esc 之外的结束方式下进程可能还在（锚定绝对路径，避免误杀）
    # 输入框关闭后焦点会回到原窗口，稍等再允许焦点变化触发自动退出
    ( sleep 0.8; rm -f "$THINGS_INSERTING" ) &

    if [ ! -f "$THINGS_NAV" ]; then
      # 输入期间已经退出了键盘模式：把已经建好的写回去就行
      write_rows
      exit 0
    fi

    if [ "${ids[$pos]}" = "$NEW_ID" ]; then
      # 取消或创建失败：去掉占位行
      ids=("${ids[@]:0:$pos}" "${ids[@]:$((pos + 1))}")
      states=("${states[@]:0:$pos}" "${states[@]:$((pos + 1))}")
      names=("${names[@]:0:$pos}" "${names[@]:$((pos + 1))}")
      [ "$2" = below ] && [ "$pos" -gt 0 ] && cursor=$((pos - 1))
      [ "$cursor" -ge ${#ids[@]} ] && cursor=$((${#ids[@]} - 1))
    fi
    write_rows; save_nav; rebuild; refresh_first
    skhd -k "f18"  # thingsinsert < f18 ; things
    ;;
esac
