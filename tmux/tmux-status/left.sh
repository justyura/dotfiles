#!/usr/bin/env bash
set -euo pipefail

current_session_id="${1:-}"
current_session_name="${2:-}"

IFS=$'\t' read -r detect_session_id detect_session_name term_width < <(
  tmux display-message -p '#{session_id}	#{session_name}	#{client_width}' 2>/dev/null || echo ""
)

[[ -z "$current_session_id" ]] && current_session_id="$detect_session_id"
[[ -z "$current_session_name" ]] && current_session_name="$detect_session_name"
term_width="${term_width:-100}"

# ── Kanagawa 调色板 ──
status_bg="#1F1F28"
inactive_bg="#2A2A37"
inactive_fg="#C8C093"
active_bg="#7E9CD8"
active_fg="#1F1F28"
separator=""
left_cap="█"
max_width=18
left_narrow_width=80

is_narrow=0
[[ "$term_width" =~ ^[0-9]+$ ]] && (( term_width < left_narrow_width )) && is_narrow=1

normalize_session_id() {
  local value="$1"
  value="${value#\$}"
  printf '%s' "$value"
}

trim_label() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+-(.*)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$value"
  fi
}

extract_index() {
  local value="$1"
  if [[ "$value" =~ ^([0-9]+)-.*$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf ''
  fi
}

get_session_icon() {
  local sid="$1"

  # Check tmux native @unread / @watching
  local unread_win
  unread_win=$(tmux list-windows -t "$sid" -F '#{@unread}' 2>/dev/null | grep -m1 '^1$' || true)
  if [[ -n "$unread_win" ]]; then
    printf '🔔'
    return
  fi
  local watching_win
  watching_win=$(tmux list-windows -t "$sid" -F '#{@watching}' 2>/dev/null | grep -m1 '^1$' || true)
  if [[ -n "$watching_win" ]]; then
    printf '⏳'
    return
  fi

  # Check agent-tracker state
  [[ -z "$tracker_state" ]] && return
  local result
  result=$(echo "$tracker_state" | jq -r --arg sid "$sid" '
    .tasks // [] | .[] | select(.session_id == $sid) |
    if .status == "in_progress" then "in_progress"
    elif .status == "completed" and .acknowledged != true then "waiting"
    else empty end
  ' 2>/dev/null | head -1 || true)
  case "$result" in
    in_progress) printf '⏳' ;;
    waiting) printf '🔔' ;;
  esac
}

# Refresh tracker cache
"$HOME/.config/tmux/tmux-status/tracker_cache.sh" 2>/dev/null || true
CACHE_FILE="/tmp/tmux-tracker-cache.json"
tracker_state=""
if [[ -f "$CACHE_FILE" ]]; then
  tracker_state=$(cat "$CACHE_FILE" 2>/dev/null || true)
fi

sessions=$(tmux list-sessions -F '#{session_id}::#{session_name}' 2>/dev/null || true)
if [[ -z "$sessions" ]]; then
  exit 0
fi

rendered=""
prev_bg=""
current_session_id_norm=$(normalize_session_id "$current_session_id")
current_session_trimmed=$(trim_label "$current_session_name")

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  session_id="${entry%%::*}"
  name="${entry#*::}"
  [[ -z "$session_id" ]] && continue

  session_id_norm=$(normalize_session_id "$session_id")
  segment_bg="$inactive_bg"
  segment_fg="$inactive_fg"
  trimmed_name=$(trim_label "$name")
  is_current=0

  if [[ "$session_id" == "$current_session_id" || "$session_id_norm" == "$current_session_id_norm" || "$trimmed_name" == "$current_session_trimmed" ]]; then
    is_current=1
    segment_bg="$active_bg"
    segment_fg="$active_fg"
  fi

  if (( is_narrow == 1 )); then
    if (( is_current == 1 )); then
      label="$trimmed_name"
    else
      idx=$(extract_index "$name")
      if [[ -n "$idx" ]]; then
        label="$idx"
      else
        label="$trimmed_name"
      fi
    fi
  else
    label="$trimmed_name"
  fi

  if (( ${#label} > max_width )); then
    label="${label:0:max_width-1}…"
  fi

  icon=$(get_session_icon "$session_id")

  if [[ -z "$prev_bg" ]]; then
    rendered+="#[fg=${segment_bg},bg=${status_bg}]${left_cap}"
  else
    rendered+="#[fg=${prev_bg},bg=${segment_bg}]${separator}"
  fi
  rendered+="#[fg=${segment_fg},bg=${segment_bg}] ${label}${icon} "
  prev_bg="$segment_bg"
done <<< "$sessions"

if [[ -n "$prev_bg" ]]; then
  rendered+="#[fg=${prev_bg},bg=${status_bg}]${separator}"
fi

printf '%s' "$rendered"
