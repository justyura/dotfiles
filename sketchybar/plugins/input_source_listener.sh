#!/bin/bash

# 启动预编译的输入法监听器
LISTENER_DIR="$(dirname "$0")"
BINARY="$LISTENER_DIR/input_source_listener_bin"

# 如果二进制不存在或源文件更新了，重新编译
SOURCE="$LISTENER_DIR/input_source_listener.swift"
if [ ! -f "$BINARY" ] || [ "$SOURCE" -nt "$BINARY" ]; then
  swiftc -O "$SOURCE" -o "$BINARY" 2>/dev/null
fi

"$BINARY" &
echo $! > /tmp/sketchybar_input_source_listener.pid
