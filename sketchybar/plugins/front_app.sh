#!/bin/bash

# $INFO 由 front_app_switched 事件自动传入
APP_NAME="$INFO"

# 空桌面时 macOS 默认聚焦 Finder，检查是否有实际窗口
if [[ "$APP_NAME" == "Finder" ]] && ! yabai -m query --windows --window &>/dev/null; then
  sketchybar --set front_app drawing=off
  exit 0
fi

case "$APP_NAME" in
  "Google Chrome") APP_NAME="Chrome" ;;
  "Microsoft Edge") APP_NAME="Edge" ;;
  "Visual Studio Code") APP_NAME="VS Code" ;;
  "IntelliJ IDEA") APP_NAME="IntelliJ" ;;
  "System Preferences") APP_NAME="Settings" ;;
  "Sublime Text") APP_NAME="Sublime" ;;
  "iTerm2") APP_NAME="iTerm" ;;
  "WezTerm") APP_NAME="Wez" ;;
esac

if [[ ${#APP_NAME} -gt 20 ]]; then
  APP_NAME="${APP_NAME:0:17}..."
fi

sketchybar --set front_app drawing=on label="$APP_NAME"
