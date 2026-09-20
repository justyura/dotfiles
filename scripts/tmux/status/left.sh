#!/usr/bin/env bash
set -euo pipefail

current_session_id="${1:-}"

# 机器是一级上下文；project 只在当前机器内导航。
inactive_fg="#8A8980"
active_fg="#DCD7BA"
active_bg="#3B3B4F"
status_bg="#1F1F28"
separator_fg="#54546D"
max_width=16

machine_badge() {
  local host="$1"
  local os="$2"
  local name icon color

  if [[ -z "$host" ]]; then
    name="MacBook"
    os="macos"
  else
    name="$host"
  fi

  # 旧 session 还没有检测缓存时，先按 Host 名做一次合理回退。
  if [[ -z "$os" ]]; then
    case "$host" in
      mini|mac|macbook*) os="macos" ;;
      arch*)             os="arch" ;;
      de|debian*)        os="debian" ;;
      ubuntu*)           os="ubuntu" ;;
      *)                 os="linux" ;;
    esac
  fi

  case "$os" in
    macos|darwin)       icon=""; color="#FFFFFF" ;;
    arch|archlinux)     icon=""; color="#1793D1" ;;
    debian|raspbian)    icon=""; color="#D70A53" ;;
    ubuntu)             icon=""; color="#E95420" ;;
    *)                  icon=""; color="#B8B8B8" ;;
  esac

  printf '#[fg=%s,bg=#3B3B4F,bold] %s %s #[bg=#1F1F28,nobold]' "$color" "$icon" "$name"
}

normalize_session_id() {
  printf '%s' "${1#\$}"
}

trim_label() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+-(.*)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "$value"
  fi
}

current_ssh_host=$(tmux show-options -qv -t "$current_session_id" @ssh-host 2>/dev/null || true)
current_machine_os=$(tmux show-options -qv -t "$current_session_id" @machine-os 2>/dev/null || true)
rendered="$(machine_badge "$current_ssh_host" "$current_machine_os")"

# SSH 机器内，机器图标后直接交给 tmux 的 window/pane 导航。
if [[ -n "$current_ssh_host" ]]; then
  printf '%s' "$rendered"
  exit 0
fi

sessions=$(tmux list-sessions -F '#{session_id}::#{session_name}::#{@ssh-host}' 2>/dev/null || true)
[[ -z "$sessions" ]] && exit 0

current_session_id=$(normalize_session_id "$current_session_id")
has_project=0

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  session_id="${entry%%::*}"
  remainder="${entry#*::}"
  name="${remainder%%::*}"
  ssh_host="${remainder#*::}"

  # 远程 machine session 不属于 Mac 的 project 列表。
  [[ -n "$ssh_host" ]] && continue

  label=$(trim_label "$name")

  if (( ${#label} > max_width )); then
    label="${label:0:max_width-1}…"
  fi

  if [[ "$(normalize_session_id "$session_id")" == "$current_session_id" ]]; then
    segment_fg="$active_fg"
    label_format="#[fg=${segment_fg},bg=${active_bg}] ${label} #[bg=${status_bg}]"
  else
    segment_fg="$inactive_fg"
    label_format="#[fg=${segment_fg},bg=${status_bg}]${label}"
  fi

  if (( has_project == 1 )); then
    rendered+="#[fg=${separator_fg}] | "
  else
    rendered+=" "
  fi
  rendered+="#[range=session|${session_id}]${label_format}#[norange]"
  has_project=1
done <<< "$sessions"

printf '%s' "$rendered"
