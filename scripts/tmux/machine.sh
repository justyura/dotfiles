#!/usr/bin/env bash

# Shared local-machine detection for tmux status and session selection.

dotfiles_machine_name() {
  local name
  name="${DOTFILES_MACHINE_NAME:-}"
  if [[ -z "$name" && -r "$HOME/.config/local/machine_name" ]]; then
    name=$(<"$HOME/.config/local/machine_name")
  fi
  if [[ -z "$name" ]]; then
    name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)
  fi
  name="${name%%.*}"
  name=$(printf '%s' "$name" | tr -cd '[:alnum:]_.-')
  printf '%s' "${name:-machine}"
}

dotfiles_machine_os() {
  local machine_os
  machine_os="${DOTFILES_MACHINE_OS:-}"
  if [[ -n "$machine_os" ]]; then
    printf '%s' "${machine_os,,}"
    return
  fi

  case "$(uname -s 2>/dev/null)" in
    Darwin) printf '%s' macos ;;
    Linux)
      if [[ -r /etc/os-release ]]; then
        machine_os=$(sed -n 's/^ID=//p' /etc/os-release | head -n 1 | tr -d "\"'")
      fi
      printf '%s' "${machine_os:-linux}"
      ;;
    *) printf '%s' linux ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'name=%s os=%s\n' "$(dotfiles_machine_name)" "$(dotfiles_machine_os)"
fi
