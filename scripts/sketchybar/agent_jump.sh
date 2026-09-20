#!/bin/bash

# 点击会话标签/弹窗行：切到该会话所在的 tmux pane 并把 iTerm 提到前台，同时标记为已处理；
# 不在 tmux 里的会话（桌面 app）则切到 app 所在空间并打开（Codex 直接定位到该会话）
# 用法: agent_jump.sh <agents 状态文件>

PLUGIN_DIR="$HOME/.config/scripts/sketchybar"
source "$PLUGIN_DIR/agent_lib.sh"

FILE=$1
[ -f "$FILE" ] || exit 0

PROVIDER=$(jq -r '.provider' "$FILE")
PANE=$(jq -r '.pane_id // empty' "$FILE")
GROUP=agents

# 鼠标选中和 Enter 共用退出路径，防止 j/k 模式留在其它窗口。
if [ -f "$HOME/.cache/sketchybar/agent_switch_selected" ]; then
  "$PLUGIN_DIR/agent_switch.sh" close
  /opt/homebrew/bin/skhd -k "f20"
fi

# 收起弹窗并清掉该组的悬停状态（弹窗隐藏后收不到 mouse.exited）
rm -f "$HOME/.cache/sketchybar/hover/$GROUP" "$HOME/.cache/sketchybar/hover/$GROUP".*
rm -f "$HOME/.cache/sketchybar/agent_preview_pinned"
sketchybar --set agents.switcher popup.drawing=off

agent_mark_seen "$FILE"
sketchybar --trigger agent_status_change

if [ -n "$PANE" ] && tmux display -p -t "$PANE" '#{pane_id}' >/dev/null 2>&1; then
  # 用最近活跃的 tmux client（sketchybar 脚本本身不在任何 client 里）
  CLIENT=$(tmux list-clients -F '#{client_activity} #{client_name}' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)
  [ -n "$CLIENT" ] && tmux switch-client -c "$CLIENT" -t "$PANE"
  tmux select-window -t "$PANE"
  tmux select-pane -t "$PANE"
  # 可能是在其它空间点击的，先切回终端所在的 1 号空间；iTerm 已在前台时不再重复激活
  # （鼠须管对 iTerm 设了 ascii_mode，每次激活 iTerm 都会被强制切回英文）
  if [[ "$(/opt/homebrew/bin/yabai -m query --windows --window 2>/dev/null | jq -r '.app // empty')" != iTerm* ]]; then
    /opt/homebrew/bin/yabai -m space --focus 1 2>/dev/null
    open -a iTerm
  fi
else
  # 桌面 app 的会话：先切到 app 所在的 yabai 空间（Claude 在 4 号，Codex 在 5 号），再打开
  SESSION=$(jq -r '.session_id // empty' "$FILE")
  case "$PROVIDER" in
    codex)
      /opt/homebrew/bin/yabai -m space --focus 5 2>/dev/null
      # ChatGPT.app 注册了 codex:// 链接，可以直接定位到这个会话
      if [ -n "$SESSION" ]; then open "codex://threads/$SESSION"; else open -b com.openai.codex; fi
      ;;
    claude)
      /opt/homebrew/bin/yabai -m space --focus 4 2>/dev/null
      open -b com.anthropic.claudefordesktop
      ;;
  esac
fi
