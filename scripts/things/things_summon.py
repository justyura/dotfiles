#!/usr/bin/python3
"""Serialize one summon; coalesce duplicate presses and never leave stale locks."""
import fcntl
import os
from pathlib import Path
import subprocess
import sys

state = Path(os.environ.get('TMPDIR', '/tmp')) / f'things_native_{os.getuid()}'
state.mkdir(parents=True, exist_ok=True)
with (state / 'summon.lock').open('a') as lock:
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)
    env = dict(os.environ, THINGS_SUMMON_LOCKED='1')
    # Both parent and child own the descriptor: even if the launcher is interrupted,
    # the actual summon retains its lock until it exits. No PID/lock-directory cleanup.
    result = subprocess.run(['/bin/bash', *sys.argv[1:]], env=env, pass_fds=(lock.fileno(),))
    sys.exit(result.returncode)
