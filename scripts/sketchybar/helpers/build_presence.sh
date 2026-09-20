#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
app="$here/StandupPresence.app"
mkdir -p "$app/Contents/MacOS"
swiftc -O "$here/presence.swift" -o "$app/Contents/MacOS/presence"
codesign --force --sign - --identifier local.yura.standup-presence "$app"
