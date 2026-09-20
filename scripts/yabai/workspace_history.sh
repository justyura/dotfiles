#!/usr/bin/env bash
set -euo pipefail

yabai_bin="${YABAI_BIN:-/opt/homebrew/bin/yabai}"
jq_bin="${JQ_BIN:-/opt/homebrew/bin/jq}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
state_id="${USER:-$(id -u)}"
state_dir="${TMPDIR:-/tmp}"
history_file="$state_dir/yabai_workspace_history_${state_id}"
sequence_file="$state_dir/yabai_workspace_sequence_${state_id}"
sequence_state="$state_dir/yabai_workspace_sequence_state_${state_id}"
expected_file="$state_dir/yabai_workspace_expected_${state_id}"
lock_dir="$state_dir/yabai_workspace_history_lock_${state_id}"
hud_source="$script_dir/workspace_hud.swift"
hud_bin="$state_dir/yabai_workspace_hud_${state_id}"
hud_pid_file="$state_dir/yabai_workspace_hud_pid_${state_id}"
watcher_source="$script_dir/workspace_option_watcher.swift"
watcher_bin="$state_dir/yabai_workspace_option_watcher_${state_id}"
watcher_pid_file="$state_dir/yabai_workspace_option_watcher_pid_${state_id}"

acquire_lock() {
  mkdir "$lock_dir" 2>/dev/null
}

release_lock() {
  rmdir "$lock_dir" 2>/dev/null || true
}

current_space() {
  "$yabai_bin" -m query --spaces --space 2>/dev/null | "$jq_bin" -r '.index // empty'
}

write_sequence_state() {
  local value="$1" temporary="${sequence_state}.tmp.$$"
  printf '%s\n' "$value" > "$temporary"
  mv "$temporary" "$sequence_state"
}

# Hot path used by the yabai signal: one query and one tiny file rewrite.
record_space() {
  local space expected updated_file
  space="${1:-$(current_space)}"
  [[ -z "$space" ]] && exit 0

  acquire_lock || exit 0
  trap release_lock EXIT

  expected=""
  if [[ -f "$expected_file" ]]; then
    expected="$(head -n 1 "$expected_file")"
    rm -f "$expected_file"
  fi

  # A switch not initiated by this script starts a fresh history sequence.
  if [[ -z "$expected" || ( "$expected" != "*" && "$space" != "$expected" ) ]]; then
    rm -f "$sequence_file" "$sequence_state"
    if [[ -f "$hud_pid_file" ]]; then
      kill "$(cat "$hud_pid_file")" 2>/dev/null || true
      rm -f "$hud_pid_file"
    fi
  fi

  touch "$history_file"
  updated_file="${history_file}.updated.$$"
  awk -v id="$space" 'BEGIN { print id } $1 != id { print $1 }' \
    "$history_file" > "$updated_file"
  mv "$updated_file" "$history_file"
}

# The slower inventory runs only when a new Option-E sequence begins.
build_sequence() {
  local current windows_file valid_file merged_file app_map_file ordered_file
  current="$(current_space)"
  windows_file="${sequence_file}.windows.$$"
  valid_file="${sequence_file}.valid.$$"
  merged_file="${sequence_file}.merged.$$"
  app_map_file="${sequence_file}.apps.$$"
  ordered_file="${sequence_file}.ordered.$$"

  "$yabai_bin" -m query --windows > "$windows_file"

  {
    [[ -n "$current" ]] && printf '%s\n' "$current"
    "$jq_bin" -r '[.[] | select(.["is-minimized"] != true) | .space | select(. > 0)] | unique[]' \
      "$windows_file"
  } | awk '!seen[$1]++' > "$valid_file"

  touch "$history_file"
  awk '
    FNR == NR { valid[$1] = 1; all[++count] = $1; next }
    valid[$1] && !seen[$1]++ { print $1 }
    END {
      for (i = 1; i <= count; i++) {
        if (!seen[all[i]]++) print all[i]
      }
    }
  ' "$valid_file" "$history_file" > "$merged_file"
  # The origin is always the first item in both history and the HUD.
  awk -v current="$current" 'BEGIN { print current } $1 != current { print $1 }' \
    "$merged_file" > "$ordered_file"
  mv "$ordered_file" "$history_file"

  # Cache application PIDs once; the persistent HUD resolves native icons.
  "$jq_bin" -r '
    [.[] | select(.["is-minimized"] != true and .space > 0)]
    | group_by(.space)[]
    | "\(.[0].space)\t\([.[].pid] | map(tostring) | join(","))"
  ' "$windows_file" > "$app_map_file"

  awk -F '\t' 'FNR == NR { apps[$1] = $2; next } { print $1 "\t" apps[$1] }' \
    "$app_map_file" "$history_file" > "$sequence_file"

  rm -f "$windows_file" "$valid_file" "$app_map_file"
}

prepare_hud() {
  [[ "$(uname -s)" == "Darwin" ]] || return 0
  if [[ ! -x "$hud_bin" || "$hud_source" -nt "$hud_bin" ]]; then
    /usr/bin/swiftc -O "$hud_source" -o "$hud_bin" >/dev/null 2>&1 || true
  fi
  if [[ ! -x "$watcher_bin" || "$watcher_source" -nt "$watcher_bin" ]]; then
    /usr/bin/swiftc -O "$watcher_source" -o "$watcher_bin" >/dev/null 2>&1 || true
  fi
}

start_release_watcher() {
  [[ -x "$watcher_bin" ]] || return 0

  if [[ -f "$watcher_pid_file" ]]; then
    kill "$(cat "$watcher_pid_file")" 2>/dev/null || true
  fi

  "$watcher_bin" "$sequence_state" "$sequence_file" "$expected_file" \
    "$hud_bin" "$hud_pid_file" "$watcher_pid_file" "$yabai_bin" &
  printf '%s\n' "$!" > "$watcher_pid_file"
}

navigate() {
  local direction="${1:-next}"
  local index total active watcher_pid
  active=0

  acquire_lock || exit 0
  trap release_lock EXIT

  index=0
  watcher_pid=""
  [[ -f "$watcher_pid_file" ]] && watcher_pid="$(head -n 1 "$watcher_pid_file")"
  if [[ -s "$sequence_state" && -s "$sequence_file" && -n "$watcher_pid" ]] \
     && kill -0 "$watcher_pid" 2>/dev/null; then
    index="$(head -n 1 "$sequence_state")"
    active=1
  fi

  if (( active == 0 )); then
    build_sequence
  fi

  total="$(wc -l < "$sequence_file" | tr -d ' ')"
  (( total > 0 )) || exit 0

  if (( active == 0 )); then
    if [[ "$direction" == "previous" ]] && (( total > 1 )); then
      index="$total"
    elif (( total > 1 )); then
      index=2
    else
      index=1
    fi
  elif [[ "$direction" == "previous" ]]; then
    index=$((index - 1))
    (( index < 1 )) && index="$total"
  else
    index=$((index + 1))
  fi

  (( index > total )) && index=1

  # Atomic replacement keeps the persistent HUD from observing an empty file.
  write_sequence_state "$index"

  release_lock
  trap - EXIT

  if (( active == 0 )); then
    # The watcher shows the HUD after a short hold and commits on Option-up.
    start_release_watcher
  fi
}

case "${1:-}" in
  record) record_space "${2:-}" ;;
  back|next) navigate next ;;
  previous) navigate previous ;;
  sync)
    acquire_lock || exit 0
    trap release_lock EXIT
    build_sequence
    rm -f "$sequence_state" "$expected_file"
    prepare_hud
    ;;
  *)
    printf 'usage: %s {record [space-index]|next|previous|sync}\n' "$0" >&2
    exit 2
    ;;
esac
