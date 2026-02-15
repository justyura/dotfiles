#!/usr/bin/env bash
set -euo pipefail

RUN_DIR="$HOME/.config/agent-tracker/run"
mkdir -p "$RUN_DIR"

# Record current position for jump-back
current=$(tmux display-message -p '#{session_id}:::#{window_id}:::#{pane_id}' 2>/dev/null)

# Search all windows for @unread first, then @watching
target=""
while IFS=$'\t' read -r sid wid flag; do
  if [[ "$flag" == "1" ]]; then
    target="${sid}	${wid}"
    break
  fi
done < <(tmux list-windows -a -F "#{session_id}$(printf '\t')#{window_id}$(printf '\t')#{@unread}" 2>/dev/null)

if [[ -z "$target" ]]; then
  while IFS=$'\t' read -r sid wid flag; do
    if [[ "$flag" == "1" ]]; then
      target="${sid}	${wid}"
      break
    fi
  done < <(tmux list-windows -a -F "#{session_id}$(printf '\t')#{window_id}$(printf '\t')#{@watching}" 2>/dev/null)
fi

[[ -z "$target" ]] && exit 0

# Save jump-back location
printf '%s\n' "$current" > "$RUN_DIR/jump_back.txt"

IFS=$'\t' read -r sid wid <<< "$target"
tmux switch-client -t "$sid" \; select-window -t "$wid"
