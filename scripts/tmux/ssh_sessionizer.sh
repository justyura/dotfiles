#!/usr/bin/env bash
set -euo pipefail

ssh_config="$HOME/.ssh/config"
orbstack_config="$HOME/.orbstack/ssh/config"
local_machine="macbook"

list_hosts() {
  local config
  for config in "$ssh_config" "$orbstack_config"; do
    [[ -r "$config" ]] || continue
    awk '
      tolower($1) == "host" {
        for (i = 2; i <= NF; i++) {
          if ($i !~ /[*?!]/ && $i != "github.com") print $i
        }
      }
    ' "$config"
  done | awk '!seen[$0]++'
}

detect_remote_os() {
  local detected
  detected=$(
    ssh \
      -o BatchMode=yes \
      -o ConnectTimeout=3 \
      -o ConnectionAttempts=1 \
      -o StrictHostKeyChecking=yes \
      "$1" \
      'if [ "$(uname -s 2>/dev/null)" = Darwin ]; then printf "macos\n"; elif [ -r /etc/os-release ]; then . /etc/os-release; printf "%s\n" "${ID:-linux}"; else printf "linux\n"; fi' \
      2>/dev/null | head -n 1 || true
  )
  printf '%s' "$detected" | tr '[:upper:]' '[:lower:]'
}

if [[ "${1:-}" == "--refresh-open" ]]; then
  while IFS= read -r entry; do
    session_name="${entry%%::*}"
    remainder="${entry#*::}"
    host="${remainder%%::*}"
    machine_os="${remainder#*::}"
    [[ -n "$host" && -z "$machine_os" ]] || continue

    machine_os=$(detect_remote_os "$host")
    [[ -n "$machine_os" ]] && tmux set-option -t "$session_name" @machine-os "$machine_os"
  done < <(tmux list-sessions -F '#{session_name}::#{@ssh-host}::#{@machine-os}')
  tmux refresh-client -S
  exit 0
fi

machine=$(
  {
    printf '%s\n' "$local_machine"
    list_hosts | awk -v local="$local_machine" '$0 != local'
  } | fzf \
  --prompt='Machine > ' \
  --height=100% \
  --layout=reverse \
  --border=none
)
[[ -n "$machine" ]] || exit 0

# Host 来自 SSH config，仍限制字符集，避免将内容插入 shell 命令。
[[ "$machine" =~ ^[A-Za-z0-9._-]+$ ]] || exit 1

if [[ "$machine" == "$local_machine" ]]; then
  session_name="$local_machine"
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" -n local -c "$HOME"
  fi

  # 本机 project 永远使用本地 shell，不继承 SSH project 的默认命令。
  tmux set-option -u -t "$session_name" default-command 2>/dev/null || true
  tmux set-option -u -t "$session_name" @ssh-host 2>/dev/null || true
  tmux set-option -t "$session_name" @machine-os macos
else
  host="$machine"
  session_name="ssh-${host//./-}"

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" -n "$host" "ssh $host"
  fi

  # 这个 project 内后续新建的 window/pane 也都先进入同一台机器。
  tmux set-option -t "$session_name" default-command "ssh $host"
  tmux set-option -t "$session_name" @ssh-host "$host"

  machine_os=$(tmux show-options -qv -t "$session_name" @machine-os 2>/dev/null || true)
  if [[ -z "$machine_os" ]]; then
    machine_os=$(detect_remote_os "$host")
    [[ -n "$machine_os" ]] && tmux set-option -t "$session_name" @machine-os "$machine_os"
  fi

  # 已存在的 project 如果因 SSH 断开回到了本地 shell，选中时自动重连。
  pane_command=$(tmux display-message -p -t "$session_name:" '#{pane_current_command}')
  case "$pane_command" in
    sh|bash|zsh|fish)
      tmux send-keys -t "$session_name:" "ssh $host" Enter
      ;;
  esac
fi

tmux switch-client -t "$session_name"
