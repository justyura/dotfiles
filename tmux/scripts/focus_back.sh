#!/usr/bin/env bash
set -euo pipefail

F="$HOME/.config/agent-tracker/run/jump_back.txt"
[[ ! -f "$F" ]] && exit 0

line=$(head -1 "$F")
sid="${line%%:::*}"
rest="${line#*:::}"
wid="${rest%%:::*}"
pid="${rest#*:::}"

[[ -z "${sid:-}" || -z "${wid:-}" || -z "${pid:-}" ]] && exit 0

tmux switch-client -t "$sid" \; select-window -t "$wid" \; select-pane -t "$pid"
