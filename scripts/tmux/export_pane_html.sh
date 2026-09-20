#!/usr/bin/env bash
set -euo pipefail

pane_id="${1:-}"
[[ -z "$pane_id" ]] && exit 1

timestamp=$(date +%Y%m%d_%H%M%S)
outfile="/tmp/tmux_${timestamp}.html"

tmux capture-pane -t "$pane_id" -e -p -S - -E - \
  | aha --title "tmux export $timestamp" > "$outfile"

# 上传到 secret gist（仅链接可访问）
gist_url=$(gh gist create "$outfile" 2>/dev/null || true)

if [[ -n "$gist_url" ]]; then
  gist_id="${gist_url##*/}"
  filename=$(basename "$outfile")
  raw_url="https://gist.githubusercontent.com/$(gh api user -q .login)/${gist_id}/raw/${filename}"
  preview_url="https://htmlpreview.github.io/?${raw_url}"
  printf '%s' "$preview_url" | pbcopy
  tmux display-message "Uploaded! Preview URL copied"
else
  printf '%s' "$outfile" | pbcopy
  tmux display-message "Upload failed, local path copied: $outfile"
fi
