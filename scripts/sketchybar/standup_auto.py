#!/usr/bin/env python3
"""Local activity/presence timer. Only timestamps and detector status are stored."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time
import sys
from activity_history import record
from work_progress import progress_image


def advance(state, now, idle, locked, presence, work, rest, threshold, click=False, presence_ttl=75, action=None):
    s = dict(state)
    previous = s.get('tick', now)
    dt = max(0, now - previous)
    s.setdefault('worked', 0)
    s.setdefault('alerted', False)
    s.setdefault('last_seen', now - idle)
    # Long gaps are never counted as work (sleep or stopped service).
    if dt >= rest:
        s.update(worked=0, alerted=False)
    gain = 0
    chime = False
    fresh = 0 <= now - presence.get('at', 0) <= presence_ttl
    reading = fresh and presence.get('status') == 'present' and not locked
    active = not locked and (idle < threshold or reading)
    # Clicking is navigation, never an invisible five-minute override.
    if s.pop('manual_until', None) is not None:
        s.pop('away_since', None)
    if action == 'toggle-break':
        action = 'resume' if 'break_started' in s else 'start-break'
    if action == 'start-break' and 'break_started' not in s:
        s['break_started'] = now
    if 'break_started' in s:
        elapsed = max(0, now - s['break_started'])
        if elapsed < rest and action != 'resume':
            s.update(tick=now, phase='manual_break')
            return s, 0, False
        # A completed explicit break resets work. An early return merely resumes.
        if elapsed >= rest:
            s.update(worked=0, alerted=False)
        s.pop('break_started')
        s.pop('away_since', None)
        s['last_seen'] = now
        dt = 0
        # Clicking “resume” is itself fresh activity. Reflect work immediately even if
        # the idle/presence sample was captured just before the click.
        if action == 'resume':
            active = True
            idle = 0
    if active:
        away = s.pop('away_since', None)
        if away is not None and now - away >= rest:
            s.update(worked=0, alerted=False)
        if 0 <= dt <= 30 and away is None:
            s['worked'] += dt
            gain = min(dt, max(0, work - (s['worked'] - dt)))
        s['last_seen'] = now if reading else now - idle
        phase = 'reading' if reading and idle >= threshold else 'work'
        if s['worked'] >= work:
            phase = 'due'
            if not s['alerted']:
                chime = True
                s['alerted'] = True
    else:
        if 'away_since' not in s:
            s['away_since'] = now if locked else max(now - idle, s['last_seen'])
        rested = now - s['away_since']
        phase = 'away'
        if rested >= rest:
            s.update(worked=0, alerted=False)
            phase = 'rested'
    s.update(tick=now, phase=phase)
    return s, gain, chime


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else None
    if action not in (None, 'toggle-break', 'start-break', 'resume'):
        raise SystemExit('Unknown action')
    cache = Path.home() / '.cache/sketchybar'
    cache.mkdir(parents=True, exist_ok=True)
    lock = (cache / 'standup_auto.lock').open('w')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | (0 if action else fcntl.LOCK_NB))
    except BlockingIOError:
        return  # no queued timer processes when a probe or disk is slow
    now = time.time()
    work = int(os.getenv('STANDUP_WORK_MIN', '45')) * 60
    rest = int(os.getenv('STANDUP_BREAK_MIN', '5')) * 60
    threshold = int(os.getenv('STANDUP_IDLE_SEC', '180'))
    app = Path.home() / '.config/scripts/sketchybar/helpers/StandupPresence.app'
    binary = app / 'Contents/MacOS/presence'
    try:
        activity = json.loads(subprocess.check_output([str(binary), '--idle'], timeout=2))
    except (OSError, ValueError, subprocess.SubprocessError):
        # Failed sensing pauses rather than accumulating phantom work.
        activity = {'idle': threshold, 'locked': True, 'unavailable': True}
    idle = max(0, activity['idle'])
    locked = activity['locked']
    path = cache / 'standup_auto.json'
    s = read_json(path)
    if not s:
        try:
            phase, start, alerted = (cache / 'standup.state').read_text().split()
            if phase == 'work':
                s = {'worked': min(work, max(0, now - int(start))), 'alerted': alerted == '1'}
        except (OSError, ValueError):
            pass
    presence = read_json(cache / 'presence.json')
    interval = max(30, int(os.getenv('STANDUP_CAMERA_INTERVAL', '60')))
    if os.getenv('STANDUP_CAMERA', '1') != '1':
        presence = {}
    if os.getenv('STANDUP_CAMERA', '1') == '1' and not locked and idle >= threshold:
        if now - s.get('camera_requested', 0) >= interval:
            try:
                subprocess.run(['/usr/bin/open', '-g', str(app), '--args', '--sample'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3)
            except (OSError, subprocess.SubprocessError):
                pass
            s['camera_requested'] = now
    s, gain, chime = advance(s, now, idle, locked, presence, work, rest, threshold,
                             os.getenv('SENDER') == 'mouse.clicked', interval + 15, action)
    record(now, dict(activity, manual_break=s['phase'] == 'manual_break'), presence, threshold, interval + 15)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(s))
    tmp.replace(path)
    if gain:
        directory = Path.home() / '.local/share/sketchybar/focus'
        directory.mkdir(parents=True, exist_ok=True)
        daily = directory / time.strftime('%Y-%m-%d')
        try:
            total = int(daily.read_text())
        except (OSError, ValueError):
            total = 0
        temp = daily.with_suffix('.tmp')
        temp.write_text(str(total + round(gain)))
        temp.replace(daily)
    if chime:
        subprocess.Popen(['/usr/bin/afplay', os.getenv('STANDUP_SOUND', '/System/Library/Sounds/Glass.aiff')],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    phase = s['phase']
    remaining = max(0, work - s['worked'])
    if phase == 'manual_break':
        glyph, label, color = 'Ⅱ', '休息', '0xff88b5d4'
    elif phase == 'due':
        glyph, label, color = '!', '起身', '0xffcc7d87'
    elif phase == 'rested':
        glyph, label, color = 'Ⅱ', '已休息', '0xff929baa'
    elif phase == 'away':
        glyph, label, color = 'Ⅱ', '暂停', '0xff929baa'
    else:
        glyph = 'R' if phase == 'reading' else 'W'
        label, color = f'{max(1, int(remaining / 60))}m', '0xffb7d69a'
    percent = min(100, int(s['worked'] / work * 100))
    print(json.dumps({'glyph': glyph, 'label': label, 'color': color,
                      'percent': percent, 'image': progress_image(percent, color),
                      'break_label': '提前结束 · 恢复工作' if phase == 'manual_break' else f'开始休息 · {rest // 60} 分钟',
                      'phase': phase, 'camera': presence.get('status', 'pending')}))


if __name__ == '__main__':
    main()
