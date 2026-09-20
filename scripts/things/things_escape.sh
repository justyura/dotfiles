#!/bin/bash
# Lifecycle only. This script is NEVER invoked by Escape itself.
set -eu
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
helper="$script_dir/things_escape"
state="${TMPDIR:-/tmp}/things_escape_${UID}"
mkdir -p "$state"
if [ ! -x "$helper" ] || [ "$script_dir/things_escape.swift" -nt "$helper" ]; then
    /usr/bin/swiftc -module-cache-path "$state/module-cache" -O "$script_dir/things_escape.swift" -o "$helper.build.$$"
    mv "$helper.build.$$" "$helper"
fi
case "${1:---start}" in
    --build) exit 0 ;;
    --inspect|--self-test|--running|--request-permission) exec "$helper" "$1" ;;
    --start)
        # A loaded KeepAlive agent already retries. kickstart can block until its
        # throttle expires when permission is missing, stalling the summon lock.
        if "$helper" --running; then exit 0; fi
        if /bin/launchctl print "gui/${UID}/com.yura.things-escape" >/dev/null 2>&1; then exit 0; fi
        # Recover an unloaded agent without inheriting the caller's summon lock FD.
        agent="$HOME/Library/LaunchAgents/com.yura.things-escape.plist"
        if [ -f "$agent" ]; then
            /usr/bin/python3 - "$UID" "$agent" <<'PYTHON'
import subprocess, sys
subprocess.Popen(['/bin/launchctl', 'bootstrap', 'gui/' + sys.argv[1], sys.argv[2]],
                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 close_fds=True, start_new_session=True)
PYTHON
        fi ;;
    *) exit 2 ;;
esac
