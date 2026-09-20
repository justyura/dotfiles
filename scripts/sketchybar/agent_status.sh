#!/bin/bash

# 由 Claude Code / Codex 的 hook 调用（stdin 为 hook JSON），记录每个 agent 会话的任务状态，
# 供 agent_popup.sh 在悬停弹窗里列出。每个 tmux pane（无 pane 时按 session_id）一个文件：
#   ~/.cache/sketchybar/agents/<provider>-<key>.json
# 用法: agent_status.sh start   # UserPromptSubmit → running
#       agent_status.sh stop    # Stop → done；Notification（请求权限等）→ waiting

DIR="$HOME/.cache/sketchybar/agents"
mkdir -p "$DIR"

INPUT=$(cat)
field() { jq -r --arg raw "$INPUT" "(\$raw | fromjson? // {}) | $1 // empty" -n 2>/dev/null; }

EVENT=$(field .hook_event_name)
SESSION=$(field .session_id)
TRANSCRIPT=$(field .transcript_path)

# 区分来源：Codex 的 transcript 在 ~/.codex 下；否则看 Claude Code 注入的环境变量
if [[ "$TRANSCRIPT" == */.codex/* ]]; then
  PROVIDER=codex
elif [ -n "$CLAUDECODE" ] || [[ "$TRANSCRIPT" == */.claude/* ]]; then
  PROVIDER=claude
else
  PROVIDER=codex
fi

if [ -n "$TMUX_PANE" ]; then
  KEY="pane${TMUX_PANE#%}"
elif [ -n "$SESSION" ]; then
  KEY="$SESSION"
else
  exit 0
fi
FILE="$DIR/$PROVIDER-$KEY.json"

case "$1" in
  start)
    STATUS=running
    ;;
  stop)
    if [ "$EVENT" = Notification ]; then
      # 空闲提醒（"waiting for your input"）不改变状态，只有请求权限等才算需要处理
      TYPE=$(field .notification_type)
      MSG=$(field .message)
      if [ "$TYPE" = idle_prompt ] || [[ "$MSG" == *"waiting for your input"* ]]; then
        exit 0
      fi
      STATUS=waiting
    else
      STATUS=done
    fi
    ;;
  *) exit 0 ;;
esac

OLD=$(cat "$FILE" 2>/dev/null)
[ -n "$OLD" ] || OLD='{}'
jq -n \
  --arg raw "$INPUT" --arg old "$OLD" \
  --arg provider "$PROVIDER" --arg status "$STATUS" --arg pane "$TMUX_PANE" \
  --arg cwd "$PWD" --argjson now "$(date +%s)" '
  ($raw | fromjson? // {}) as $in
  | ($old | fromjson? // {}) as $prev
  | $prev + {
      provider: $provider,
      status: $status,
      pane_id: $pane,
      session_id: ($in.session_id // $prev.session_id),
      cwd: ($in.cwd // $prev.cwd // $cwd),
      updated_at: $now
    }
  | if $status == "running" and ($in.prompt // "") != "" then
      . + {prompt: ($in.prompt | split("\n") | map(select(test("\\S"))) | (.[0] // "") | sub("^\\s+"; "") | .[0:48]), started_at: $now}
    elif $status == "running" then
      . + {started_at: $now}
    else . end
' > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

# 通知 sketchybar 立即刷新会话标签（hook 环境不一定带 homebrew PATH）
SKETCHYBAR=$(command -v sketchybar || echo /opt/homebrew/bin/sketchybar)
"$SKETCHYBAR" --trigger agent_status_change >/dev/null 2>&1 || true
