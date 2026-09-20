#!/bin/bash
# Switch to session by its position in the list (1-based)

index="$1"
[[ -z "$index" || ! "$index" =~ ^[0-9]+$ ]] && exit 0

target=$(tmux list-sessions -F '#{session_id}' 2>/dev/null | sed -n "${index}p")
[[ -n "$target" ]] && tmux switch-client -t "$target" && tmux refresh-client -S
