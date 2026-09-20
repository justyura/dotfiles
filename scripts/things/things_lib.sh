#!/bin/bash

# day_timeline.sh / things_first.sh / things_nav.sh 共用：当前 tmux 会话 ↔ 同名 Things 3 项目
# 通过 AppleScript 读写；Things 不在运行时不会主动启动它

THINGS_ROWS="$HOME/.cache/sketchybar/things_rows"          # 清单弹窗当前的行："id<TAB>open|completed<TAB>name"
THINGS_PROJECT="$HOME/.cache/sketchybar/things_rows_project" # 这些行所属的项目名
THINGS_STATUS="$HOME/.cache/sketchybar/things_rows_status"   # ok / NOT_RUNNING / NO_PROJECT / NO_SESSION
THINGS_NAV="$HOME/.cache/sketchybar/things_nav"             # 键盘模式状态："cursor anchor"（anchor=-1 为非可视模式）
THINGS_PIN="$HOME/.cache/sketchybar/things_preview_pinned"
THINGS_INSERTING="$HOME/.cache/sketchybar/things_inserting" # o/O 输入框打开期间存在（焦点变化不触发自动退出）
THINGS_FOCUS="$HOME/.cache/sketchybar/things_nav_focus"     # 进入键盘模式时聚焦的 "窗口id 空间号"
THINGS_FOCUS_LOG="$HOME/.cache/sketchybar/things_nav_focus.log" # 焦点信号的处理记录（保留最近 50 条）
THINGS_JUMP_STATE="$HOME/.cache/sketchybar/things_jump_state" # / 跳转模式的跨进程状态（光标/行数）
THINGS_JUMP_KEYS="$HOME/.cache/sketchybar/things_jump_keys"   # / 跳转模式按下的键（每行一个 token，回放得到查询串）
THINGS_PROJECTS_CACHE="$HOME/.cache/sketchybar/things_projects" # / 跳转的候选缓存（读 Things 要 0.3s+，按下 / 时来不及）
THINGS_VIEW="$HOME/.cache/sketchybar/things_view_project" # /xxx 跳转后清单临时在看的项目（bar 上仍是当前 tmux 项目）
THINGS_RING_DIR="$HOME/.cache/sketchybar/rings"          # bar 上的进度圆环图片缓存（按 已完成_总数 命名）
THINGS_WRAP_CACHE="$HOME/.cache/sketchybar/things_wrap_cache"  # 折行结果缓存："宽度|字号|任务名<TAB>各段(\x1f 分隔)"
THINGS_SYNC_SPOOL="$HOME/.cache/sketchybar/things_sync_spool"  # 待写回 Things 的操作队列（每行 "op<TAB>arg<TAB>arg"）
THINGS_SYNC_LOCK="$HOME/.cache/sketchybar/things_sync.lock"    # 队列消费者的单实例锁（mkdir 原子）

# 弹窗尺寸：宽度 = 当前屏幕宽度的 THINGS_PANEL_WIDTH_PERCENT%，高度固定 THINGS_PANEL_LINES 行（settings.sh），超出时滚动；
# 任务名超出宽度时折行，续行缩进到与首行文字对齐
THINGS_PANEL_WIDTH="$HOME/.cache/sketchybar/things_panel_width" # 缓存的面板宽度（打开清单时 things_measure_panel 重新测量）
THINGS_SCROLL="$HOME/.cache/sketchybar/things_scroll"           # 清单滚动位置：可见区第一行的折行序号
THINGS_INDENT=40          # icon.padding_left 12 + 复选框 18 + icon.padding_right 10
THINGS_FONT_SIZE=15
THINGS_LINE_HEIGHT=28
THINGS_SCROLLOFF=2        # 光标上下至少留几行（同 vim scrolloff）
THINGS_WIDTH=700
read -r THINGS_WIDTH 2>/dev/null < "$THINGS_PANEL_WIDTH"
[[ "$THINGS_WIDTH" =~ ^[0-9]+$ ]] || THINGS_WIDTH=700
THINGS_TEXT_WIDTH=$((THINGS_WIDTH - THINGS_INDENT - 40))   # 右侧留白
: "${THINGS_PANEL_LINES:=20}"

# 按当前聚焦屏幕重新测量面板宽度（打开清单时调用一次，每次按键不查 yabai）
things_measure_panel() {
  local w
  w=$(/opt/homebrew/bin/yabai -m query --displays --display 2>/dev/null | jq -r '.frame.w // empty | floor')
  [[ "$w" =~ ^[0-9]+$ ]] || return 0
  THINGS_WIDTH=$((w * ${THINGS_PANEL_WIDTH_PERCENT:-33} / 100))
  THINGS_TEXT_WIDTH=$((THINGS_WIDTH - THINGS_INDENT - 40))
  echo "$THINGS_WIDTH" > "$THINGS_PANEL_WIDTH"
}

# 辅助程序（折行测量 / 原地输入框），源码在同目录 things_helper.swift，缺失或源码更新时自动编译
THINGS_HELPER="$HOME/.config/scripts/things/things_helper"
things_helper() {
  local src="$THINGS_HELPER.swift"
  if [ ! -x "$THINGS_HELPER" ] || [ "$src" -nt "$THINGS_HELPER" ]; then
    swiftc -O "$src" -o "$THINGS_HELPER" >/dev/null 2>&1 || return 1
  fi
  "$THINGS_HELPER" "$@"
}

# 清单配色（比 bar 上更亮，便于阅读）与复选框
# （Hack Nerd Font: nf-md-checkbox_blank_outline / checkbox_marked / minus_box）
THINGS_TEXT=0xffe4e8f7
THINGS_DONE_TEXT=0xff737aa2
THINGS_HEADER=0xff9aa5ce
THINGS_BOX_COLOR=0xffa9b1d6
THINGS_BOX_DONE_COLOR=0xff7aa2f7
THINGS_BOX_OPEN=$(printf '\363\260\204\261')
THINGS_BOX_DONE=$(printf '\363\260\204\262')
THINGS_BOX_CANCELED=$(printf '\363\260\215\265')   # nf-md-minus_box：和打勾框同一套，中间一条横线 = 这条不做了
THINGS_BOX_CANCELED_COLOR=0xfff7768e
THINGS_ROW_BG=0x00292e42      # 普通行
THINGS_CURSOR_BG=0xff3b4261   # 键盘光标所在行
THINGS_SELECT_BG=0xff2d3b63   # 可视模式选中的行
THINGS_YANK_BG=0xffff9e64     # y 复制时闪一下（同 nvim vim.hl.on_yank 的 IncSearch：tokyonight 橙底）
THINGS_YANK_TEXT=0xff1a1b26   # 闪烁时的文字颜色（橙底上用深色）

# 当前 tmux 会话名：取最近活跃的 client
current_project() {
  tmux list-clients -F '#{client_activity} #{session_name}' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

# 清单当前在看的项目：输入框里用 /xxx 跳转过就是那个项目，否则还是当前 tmux 会话
# （只影响弹窗清单，bar 上的项目名和进度始终跟着 tmux 会话走；退出清单模式时 things_nav.sh leave 会清掉）
view_project() {
  local p
  p=$(cat "$THINGS_VIEW" 2>/dev/null)
  if [ -n "$p" ]; then printf '%s\n' "$p"; else current_project; fi
}

# things_project_dir <项目名>：项目对应的工作目录（和 scripts/tmux/sessionizer.sh 同一套来源）
things_project_dir() {
  local name="$1"
  [ "$name" = config ] && { printf '%s' "$HOME/.config"; return 0; }
  [ "$name" = surge ] && {
    printf '%s' "$HOME/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents"; return 0; }
  [ -d "$HOME/personal/$name" ] && { printf '%s' "$HOME/personal/$name"; return 0; }
  [ -d "$HOME/dev/$name" ] && { printf '%s' "$HOME/dev/$name"; return 0; }
  return 1
}

# things_switch_session <项目名>：把 tmux 切到同名会话
#   已经在这个会话上 -> 什么都不做；会话已存在 -> 切过去；不存在 -> 按目录新建再切
#   找不到对应目录（Things 里有这个项目但本地没有工程）-> 返回 1，由调用方退回「只切清单视角」
things_switch_session() {
  local name="$1" dir
  [ -n "$name" ] || return 1
  [ "$name" = "$(current_project)" ] && return 0
  if ! tmux has-session -t="$name" 2>/dev/null; then
    dir=$(things_project_dir "$name") || return 1
    tmux new-session -ds "$name" -c "$dir" 2>/dev/null || return 1
  fi
  tmux switch-client -t "$name" 2>/dev/null
}

# things_projects：输出 Things 里所有未完成的项目名，每行一个
things_projects() {
  osascript <<'END' 2>/dev/null
tell application "System Events" to set isRunning to (exists process "Things3")
if not isRunning then return ""
tell application "Things3"
  set out to {}
  repeat with p in (projects whose status is open)
    set end of out to name of p
  end repeat
  set AppleScript's text item delimiters to linefeed
  return out as text
end tell
END
}

# things_fuzzy <查询>：stdin 每行一个候选，按 fzf 那样的子序列模糊匹配打分，从高到低输出
# 打分：连续命中 +8，命中在开头 +4，整体从开头起匹配 +6，名字越短越靠前；查询为空时不输出
things_fuzzy() {
  perl -CSD -e '
    use utf8;
    my $q = lc(shift // "");
    exit 0 unless length $q;
    my @qc = split //, $q;
    my @out;
    while (my $line = <STDIN>) {
      chomp $line;
      next unless length $line;
      my $l = lc $line;
      my ($i, $score, $prev, $start, $ok) = (0, 0, -2, -1, 1);
      for my $c (@qc) {
        my $pos = index($l, $c, $i);
        if ($pos < 0) { $ok = 0; last }
        $start = $pos if $start < 0;
        $score += 8 if $pos == $prev + 1;
        $score += 4 if $pos == 0;
        $prev = $pos; $i = $pos + 1;
      }
      next unless $ok;
      $score += 6 if $start == 0;
      $score -= length($l) / 10;
      push @out, [$score, $line];
    }
    for my $r (sort { $b->[0] <=> $a->[0] or length($a->[1]) <=> length($b->[1]) } @out) {
      print "$r->[1]\n";
    }
  ' "$1"
}

# things_todos <项目名>：输出未完成待办，每行 "id<TAB>name"；或单行 NOT_RUNNING / NO_PROJECT
things_todos() {
  osascript - "$1" <<'END' 2>/dev/null
on run argv
  tell application "System Events" to set isRunning to (exists process "Things3")
  if not isRunning then return "NOT_RUNNING"
  set projectName to item 1 of argv
  tell application "Things3"
    set matches to (projects whose name is projectName)
    if (count of matches) is 0 then return "NO_PROJECT"
    set out to {}
    repeat with t in (to dos of (item 1 of matches) whose status is open)
      set end of out to (id of t) & tab & (name of t)
    end repeat
    set AppleScript's text item delimiters to linefeed
    return out as text
  end tell
end run
END
}

# things_list <项目名>：清单弹窗用，未完成待办 + 今天完成/取消的待办（便于反悔），
# 每行 "id<TAB>open|completed|canceled<TAB>name"；或单行 NOT_RUNNING / NO_PROJECT
things_list() {
  osascript - "$1" <<'END' 2>/dev/null
on run argv
  tell application "System Events" to set isRunning to (exists process "Things3")
  if not isRunning then return "NOT_RUNNING"
  set projectName to item 1 of argv
  set todayStart to (current date) - (time of (current date))
  tell application "Things3"
    set matches to (projects whose name is projectName)
    if (count of matches) is 0 then return "NO_PROJECT"
    set p to item 1 of matches
    set out to {}
    repeat with t in (to dos of p whose status is open)
      set end of out to (id of t) & tab & "open" & tab & (name of t)
    end repeat
    repeat with t in (to dos of p whose status is completed and completion date ≥ todayStart)
      set end of out to (id of t) & tab & "completed" & tab & (name of t)
    end repeat
    repeat with t in (to dos of p whose status is canceled and completion date ≥ todayStart)
      set end of out to (id of t) & tab & "canceled" & tab & (name of t)
    end repeat
    set AppleScript's text item delimiters to linefeed
    return out as text
  end tell
end run
END
}

# things_wrap <宽度> <字号>：stdin 每行一个任务名，stdout 每行对应的折行结果（各段 \x1f 分隔）
# 命中缓存的直接输出，只有新任务名才调用 things_helper（省去每次启动 Swift 程序的时间）
things_wrap() {
  local width=$1 size=$2 names=() name misses=() seg i
  while IFS= read -r name; do names+=("$name"); done
  [ ${#names[@]} -gt 0 ] || return 0
  mkdir -p "$(dirname "$THINGS_WRAP_CACHE")"
  touch "$THINGS_WRAP_CACHE"

  # 找出缓存里没有的任务名，一次性测量后追加进缓存（只保留最近 500 条）
  while IFS= read -r name; do misses+=("$name"); done < <(
    printf '%s\n' "${names[@]}" | awk -F'\t' -v k="$width|$size|" '
      FILENAME == ARGV[1] { if (index($0, k) == 1) seen[substr($1, length(k) + 1)] = 1; next }
      !($0 in seen) && !dup[$0]++ { print }' "$THINGS_WRAP_CACHE" -)
  if [ ${#misses[@]} -gt 0 ]; then
    i=0
    while IFS= read -r seg; do
      printf '%s|%s|%s\t%s\n' "$width" "$size" "${misses[$i]}" "$seg"
      i=$((i + 1))
    done < <(printf '%s\n' "${misses[@]}" | things_helper wrap "$width" "$size") >> "$THINGS_WRAP_CACHE"
    tail -n 500 "$THINGS_WRAP_CACHE" > "$THINGS_WRAP_CACHE.tmp" && mv "$THINGS_WRAP_CACHE.tmp" "$THINGS_WRAP_CACHE"
  fi

  printf '%s\n' "${names[@]}" | awk -F'\t' -v k="$width|$size|" '
    FILENAME == ARGV[1] { if (index($0, k) == 1) cache[substr($1, length(k) + 1)] = substr($0, length($1) + 2); next }
    { print (($0 in cache) ? cache[$0] : $0) }' "$THINGS_WRAP_CACHE" -
}

# things_open_cmd <待办 id>：在当前桌面的 Things 原生浮窗中定位待办
things_open_cmd() {
  echo "$HOME/.config/scripts/things/things_open.sh $1"
}

# things_set_status <open|completed|canceled> <id>...：批量设置待办状态（与在 Things 里勾选/取消一致）
things_set_status() {
  osascript - "$@" <<'END' >/dev/null 2>&1
on run argv
  set newStatus to item 1 of argv
  tell application "Things3"
    repeat with i from 2 to count of argv
      set t to to do id (item i of argv)
      if newStatus is "completed" then
        set status of t to completed
      else if newStatus is "canceled" then
        set status of t to canceled
      else
        set status of t to open
      end if
    end repeat
  end tell
end run
END
}

# things_reorder <项目名> <逗号分隔的 id>：按给定顺序重排项目内待办（Things 隐藏的实验性命令）
things_reorder() {
  osascript - "$1" "$2" <<'END' >/dev/null 2>&1
on run argv
  tell application "Things3"
    set p to item 1 of (projects whose name is (item 1 of argv))
    _private_experimental_ reorder to dos in p with ids (item 2 of argv)
  end tell
end run
END
}

# things_create <项目名> <任务名>：在项目中新建待办，输出新待办 id
things_create() {
  osascript - "$1" "$2" <<'END' 2>/dev/null
on run argv
  tell application "Things3"
    set p to item 1 of (projects whose name is (item 1 of argv))
    set t to make new to do with properties {name:(item 2 of argv)} at end of p
    return id of t
  end tell
end run
END
}

# things_delete <id>...：删除待办（与在 Things 里删除一致，进废纸篓）
things_delete() {
  osascript - "$@" <<'END' >/dev/null 2>&1
on run argv
  tell application "Things3"
    repeat with i from 1 to count of argv
      delete to do id (item i of argv)
    end repeat
  end tell
end run
END
}

# ===== 写回队列 =====
# 清单上的操作（勾选/删除/调序）先在界面上按乐观结果渲染，AppleScript 写回排进队列由
# things_sync.sh 串行执行（一次写回 0.2s 左右，同步做会让每次按键都卡住）。

# 消费者被杀掉时锁目录会残留，导致之后的写回永远排不出去：锁里的 pid 不在了就清掉
things_sync_unstale() {
  local pid
  [ -d "$THINGS_SYNC_LOCK" ] || return 0
  pid=$(cat "$THINGS_SYNC_LOCK/pid" 2>/dev/null)
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then rm -rf "$THINGS_SYNC_LOCK"; fi
}

# things_enqueue <op> <arg>...：排队一次写回并立刻返回
#   status <open|completed> <空格分隔 id>   delete <空格分隔 id>   order <项目名> <逗号分隔 id>
things_enqueue() {
  local line
  mkdir -p "$(dirname "$THINGS_SYNC_SPOOL")"
  printf -v line '%s\t' "$@"
  printf '%s\n' "${line%$'\t'}" >> "$THINGS_SYNC_SPOOL"
  things_sync_unstale
  # 已有消费者在跑就不再 fork（它会顺带消费掉这条）
  [ -d "$THINGS_SYNC_LOCK" ] || ( "$HOME/.config/scripts/things/things_sync.sh" & ) >/dev/null 2>&1
}

# things_sync_wait：队列还没落地时先等一会儿再读 Things，
# 否则后台读到的是写回前的旧状态，会把界面上的乐观结果覆盖回去
things_sync_wait() {
  local i=0
  things_sync_unstale
  while [ -s "$THINGS_SYNC_SPOOL" ] || [ -d "$THINGS_SYNC_LOCK" ]; do
    [ "$i" -ge 50 ] && return 1   # 最多等 5 秒（写回卡住时不拖死读取）
    sleep 0.1
    i=$((i + 1))
  done
  return 0
}

# things_log_completed：把已完成/已取消的待办归档进 Logbook（等同 Things 的 "Log completed items now"）
things_log_completed() {
  osascript -e 'tell application "Things3" to log completed now' >/dev/null 2>&1
}
