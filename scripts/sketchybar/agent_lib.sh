#!/bin/bash

# agent_bar.sh / agent_popup.sh / agent_jump.sh 共用：读取 agent_status.sh（hook）记录的会话
# 状态：running 运行中 / waiting 等你处理 / done 已完成未查看 / seen 已完成且看过

AGENT_DIR="$HOME/.cache/sketchybar/agents"

# 把会话标记为“已处理”：done → seen；waiting → running（批准后 agent 会继续跑，直到下次 Stop）
agent_mark_seen() {
  local f=$1
  jq 'if .status == "done" then .status = "seen" elif .status == "waiting" then .status = "running" else . end' \
    "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
}

# agent_rows <provider>
# 输出排序后的行 "prio|updated|status|started|loc|prompt|file"（等待处理 → 已完成 → 运行中 → 已查看，同级按更新时间倒序）
# 顺带：清掉 pane 已关闭/agent 已退出的记录；iTerm 在前台且 tmux 正显示该 pane 时视为已查看
agent_rows() {
  local provider=$1 now panes active="" f status pane updated started prompt cwd line cmd sess win loc prio
  local rows=()
  now=$(date +%s)
  panes=$(tmux list-panes -a -F '#{pane_id}|#{session_name}|#{window_index}|#{pane_current_command}' 2>/dev/null)
  if [[ "$(yabai -m query --windows --window 2>/dev/null | jq -r '.app // empty')" == iTerm* ]]; then
    active=$(tmux list-clients -F '#{pane_id}' 2>/dev/null)
  fi

  for f in "$AGENT_DIR/$provider"-*.json; do
    [ -f "$f" ] || continue
    # \x1f 分隔（tab 属于空白 IFS，空字段会被合并导致错位）
    IFS=$'\x1f' read -r status pane updated started prompt cwd < <(
      jq -r '[.status, (.pane_id // ""), .updated_at, (.started_at // .updated_at), (.prompt // ""), (.cwd // "")] | map(tostring) | join("")' "$f"
    )

    if [ -n "$pane" ]; then
      line=$(grep "^$pane|" <<< "$panes")
      cmd=${line##*|}
      if [ -z "$line" ] || [[ "$cmd" =~ ^-?(zsh|bash|fish|sh)$ ]]; then
        rm -f "$f"
        continue
      fi
      IFS='|' read -r _ sess win _ <<< "$line"
      loc="$sess:$win"
      if [[ "$status" == done || "$status" == waiting ]] && grep -qx -- "$pane" <<< "$active"; then
        agent_mark_seen "$f"
        [ "$status" = done ] && status=seen || status=running
      fi
    else
      # 无 pane 的会话（桌面 app）：关掉会话时常收不到 Stop hook，状态会卡在 running
      #   running 30 分钟没更新 → 视为已结束（标成 seen，不再提醒）；seen 2 小时 / 其它 12 小时未更新 → 清掉
      if [ "$status" = running ] && [ $((now - updated)) -gt 1800 ]; then
        jq '.status = "seen"' "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
        status=seen
      fi
      if [ "$status" = seen ] && [ $((now - updated)) -gt 7200 ]; then rm -f "$f"; continue; fi
      if [ $((now - updated)) -gt 43200 ]; then rm -f "$f"; continue; fi
      loc="App·${cwd##*/}"
    fi

    case "$status" in
      waiting) prio=0 ;;
      done) prio=1 ;;
      running) prio=2 ;;
      *) prio=3 ;;
    esac
    rows+=("$prio|$updated|$status|$started|${loc//|//}|${prompt//|//}|$f")
  done

  [ ${#rows[@]} -gt 0 ] && printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1n -k2,2nr
}

# agent_rows_all：Claude 与 Codex 合并排序（provider 可从文件名 <provider>-<key>.json 取得）
agent_rows_all() {
  { agent_rows claude; agent_rows codex; } | sort -t'|' -k1,1n -k2,2nr
}

# 秒数 → "3d" / "2h5m" / "12m" / "<1m"
agent_ago() {
  local s=$1
  if [ "$s" -ge 86400 ]; then echo "$((s / 86400))d"
  elif [ "$s" -ge 3600 ]; then echo "$((s / 3600))h$(((s % 3600) / 60))m"
  elif [ "$s" -ge 60 ]; then echo "$((s / 60))m"
  else echo "<1m"; fi
}

# agent_session_lines：会话面板（悬停 / option+a）的行，顺序为
#   当前正在看的会话（iTerm 在前台时 tmux 显示的 pane，标记 current）→ 已完成/等你处理 → 其余按最近活跃排序
# 每行 "状态文件<TAB>状态<TAB>会话:窗口<TAB>app bundle id<TAB>prompt<TAB>时长<TAB>current|"
agent_session_lines() {
  local active="" now current=() pending=() others=() prio updated status started loc prompt f pane bundle when line
  if [[ "$(/opt/homebrew/bin/yabai -m query --windows --window 2>/dev/null | jq -r '.app // empty')" == iTerm* ]]; then
    # 开着多个 iTerm 窗口时有多个 tmux client，只取前台那个：优先 focused 标记，否则取最近有操作的
    active=$(tmux list-clients -F '#{?#{m:*focused*,#{client_flags}},1,0} #{client_activity} #{pane_id}' 2>/dev/null |
      sort -k1,1nr -k2,2nr | head -1 | cut -d' ' -f3)
  fi
  now=$(date +%s)
  while IFS='|' read -r prio updated status started loc prompt f; do
    [ -n "$f" ] || continue
    pane=$(jq -r '.pane_id // empty' "$f")
    case "$(basename "$f")" in
      claude-*) bundle=com.anthropic.claudefordesktop ;;
      *) bundle=com.openai.codex ;;
    esac
    case "$status" in
      running) when="$(agent_ago $((now - started)))" ;;
      waiting) when="needs input" ;;
      *) when="done $(agent_ago $((now - updated))) ago" ;;
    esac
    line="$f"$'\t'"$status"$'\t'"$loc"$'\t'"$bundle"$'\t'"${prompt//$'\t'/ }"$'\t'"$when"
    if [ -n "$pane" ] && grep -qx -- "$pane" <<< "$active"; then current+=("$line"$'\t'current)
    elif [ "$prio" -le 1 ]; then pending+=("$line"$'\t')
    else others+=("$updated"$'\t'"$line"$'\t'); fi
  done < <(agent_rows_all)
  [ ${#current[@]} -gt 0 ] && printf '%s\n' "${current[@]}"
  [ ${#pending[@]} -gt 0 ] && printf '%s\n' "${pending[@]}"
  [ ${#others[@]} -gt 0 ] && printf '%s\n' "${others[@]}" | sort -t$'\t' -k1,1nr | cut -f2-
  return 0
}
