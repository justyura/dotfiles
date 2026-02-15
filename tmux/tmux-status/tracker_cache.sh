#!/usr/bin/env bash
# Cache tracker state to avoid calling tracker-client on every status refresh
# Only refreshes if cache is older than 2 seconds

CACHE_FILE="/tmp/tmux-tracker-cache.json"
CLIENT="$HOME/.config/agent-tracker/bin/tracker-client"

[[ ! -x "$CLIENT" ]] && exit 0

# Check cache age
if [[ -f "$CACHE_FILE" ]]; then
  age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
  (( age < 2 )) && exit 0
fi

"$CLIENT" state 2>/dev/null > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
