#!/usr/bin/env bash
set -euo pipefail

surge_entry="surge"
surge_config_dir="$HOME/Library/Mobile Documents/iCloud~com~nssurge~inc/Documents"

list_entries() {
  find "$HOME/personal" -maxdepth 1 -mindepth 1 -type d 2>/dev/null
  printf '%s\n' "$HOME/.config"

  if [[ "$(uname -s)" == "Darwin" ]] && [[ -d "$surge_config_dir" ]]; then
    printf '%s\n' "$surge_entry"
  fi
}

selected="$(list_entries | fzf)"
[[ -z "$selected" ]] && exit 0

if [[ "$selected" == "$surge_entry" ]]; then
  selected="$surge_config_dir"
  selected_name="surge"
  initial_window="config"
else
  selected_name="$(basename "$selected" | sed 's/^\.*//' | tr '.,: ' '____')"
  initial_window=""
fi

switch_to() {
  if [[ -z "${TMUX:-}" ]]; then
    tmux attach-session -t "$selected_name"
  else
    tmux switch-client -t "$selected_name"
  fi
}

if tmux has-session -t="$selected_name" 2>/dev/null; then
  switch_to
else
  if [[ -n "$initial_window" ]]; then
    tmux new-session -ds "$selected_name" -n "$initial_window" -c "$selected"
  else
    tmux new-session -ds "$selected_name" -c "$selected"
  fi
  if [[ -x "$selected/.ready-tmux" ]]; then
    "$selected/.ready-tmux" "$selected_name" "$selected"
  fi
  switch_to
fi
