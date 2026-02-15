#!/bin/bash
# Switch to session by its index number (1-based)

index="$1"

if [[ -z "$index" || ! "$index" =~ ^[0-9]+$ ]]; then
  exit 0
fi

target=$(tmux list-sessions -F '#{session_id} #{session_name}' 2>/dev/null \
  | awk -v idx="$index" '$2 ~ "^"idx"-" {print $1; exit}')

if [[ -n "$target" ]]; then
  tmux switch-client -t "$target"
  tmux refresh-client -S
fi
