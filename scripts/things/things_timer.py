#!/usr/bin/env python3
"""Explicit task stopwatch; local atomic state, no Things mutations or input tracking."""
import argparse
from contextlib import contextmanager
from copy import deepcopy
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

ROOT = Path(os.environ.get('THINGS_TIMER_DIR', Path.home() / '.local/share/things-timer'))
BAR = Path.home() / '.local/bin/focus_bar'
REMINDER_SECONDS = 25 * 60


def elapsed(active, now):
    return max(0, active['elapsed'] + (max(0, now - active['running_since']) if active['running_since'] is not None else 0))


def transition(state, action, now, task=None):
    state = deepcopy(state)
    active = state.get('active')
    if action == 'toggle' and task and (not active or active['task']['id'] != task['id']):
        if active:
            state = transition(state, 'finish', now)
            state['sessions'][-1]['end_reason'] = 'switched'
        state['active'] = {'session_id': str(uuid.uuid4()), 'task': task, 'started_at': now,
                           'running_since': now, 'elapsed': 0, 'next_reminder': REMINDER_SECONDS,
                           'reminder': False, 'pause_reason': None}
        return state
    if not active:
        return state
    if action == 'finish':
        state.setdefault('sessions', []).append({**active, 'ended_at': now, 'elapsed': elapsed(active, now),
                                                'running_since': None, 'reminder': False})
        state['active'] = None
    elif action in ('toggle', 'pause'):
        if active['running_since'] is not None:
            active['elapsed'] = elapsed(active, now)
            active['running_since'] = None
            active['pause_reason'] = 'sleep' if action == 'pause' else 'manual'
            active['reminder'] = False
        elif action == 'toggle':
            active['running_since'] = now
            active['pause_reason'] = None
            active['next_reminder'] = elapsed(active, now) + REMINDER_SECONDS
    elif action == 'ack':
        active['reminder'] = False
        active['next_reminder'] = elapsed(active, now) + REMINDER_SECONDS
    elif action == 'tick' and active['running_since'] is not None:
        if elapsed(active, now) >= active['next_reminder']:
            active['reminder'] = True
    return state


@contextmanager
def locked_state(root=ROOT):
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (root / 'state.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = root / 'state.json'
        state = json.loads(path.read_text()) if path.exists() else {'schema': 1, 'active': None, 'sessions': []}
        if state.get('schema') != 1:
            raise ValueError('Unknown timer state schema')
        yield state


def save(state, root=ROOT):
    fd, tmp = tempfile.mkstemp(prefix='.state-', dir=root)
    try:
        with os.fdopen(fd, 'w') as file:
            json.dump(state, file, ensure_ascii=False)
            file.flush()
            os.fsync(file.fileno())
        os.replace(tmp, root / 'state.json')
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def clock_text(seconds):
    seconds = int(seconds)
    hours, rest = divmod(seconds, 3600)
    minutes, seconds = divmod(rest, 60)
    return f'{hours:02d}:{minutes:02d}:{seconds:02d}' if hours else f'{minutes:02d}:{seconds:02d}'


def short(text, length):
    text = ' '.join(str(text).split())
    return text if len(text) <= length else text[:length-1] + '…'


def view(state, now):
    active = state.get('active')
    notice = state.get('notice', {})
    notice_text = notice.get('text', '') if now < notice.get('expires_at', 0) else ''
    if not active:
        last = state.get('sessions', [])[-1:]
        note = f"上次 {clock_text(last[0]['elapsed'])} · {short(last[0]['task']['name'], 35)}" if last else 'n 安排到 Now · N 查看 · p 开始计时'
        return {'project': 'NOW', 'task': '准备开始下一件事', 'clock': '00:00', 'status': '未开始',
                'toggle': '开始', 'reminder': notice_text or note, 'color': '0xff929baa', 'active': False}
    paused = active['running_since'] is None
    reminder = '还在做这件事吗？点此继续专注' if active['reminder'] else ''
    if active.get('sync_error'):
        reminder = '暂时无法同步 Things 状态'
    if active.get('pause_reason') == 'sleep':
        reminder = '睡眠时已暂停 · 点击继续'
    return {'project': short(active['task'].get('project_name') or 'Things', 24),
            'task': short(active['task']['name'], 65), 'clock': clock_text(elapsed(active, now)),
            'status': '已暂停' if paused else '进行中', 'toggle': '继续' if paused else '暂停',
            'reminder': notice_text or reminder, 'color': '0xffe0af68' if paused or active['reminder'] else '0xff9ece6a', 'active': True}


def render(state, now):
    if os.environ.get('THINGS_TIMER_NO_RENDER') == '1':
        return
    data = view(state, now)
    cache_path = ROOT / 'render.json'
    try:
        previous = json.loads(cache_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        previous = {}
    values = {
        'focus.project': {'label': data['project']},
        'focus.task': {'label': data['task']},
        'focus.status': {'label': data['status'], 'label.color': data['color']},
        'focus.clock': {'label': data['clock'], 'label.color': data['color']},
        'focus.toggle': {'label': data['toggle'], 'drawing': 'on' if data['active'] else 'off'},
        'focus.reminder': {'label': data['reminder'], 'label.color': data['color']},
    }
    arguments = []
    for item, props in values.items():
        changed = {k: v for k, v in props.items() if previous.get(item, {}).get(k) != v}
        if changed:
            arguments += ['--set', item] + [f'{k}={v}' for k, v in changed.items()]
    if arguments and BAR.exists():
        result = subprocess.run([str(BAR), *arguments], capture_output=True, timeout=2)
        if result.returncode == 0:
            cache_path.write_text(json.dumps(values))


def selected_task():
    script = Path(__file__).with_name('things_timer_selection.js')
    result = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript', str(script)],
                            capture_output=True, text=True, timeout=4, check=True)
    return json.loads(result.stdout)


def apply_lifecycle(state, session_id, info, now):
    active = state.get('active')
    if not active or active['session_id'] != session_id:
        return state
    status = info.get('status')
    if status in ('completed', 'canceled', 'deleted'):
        ended = info.get('ended_at')
        ended = min(now, max(active['started_at'], ended)) if isinstance(ended, (int, float)) else now
        result = transition(state, 'finish', ended)
        result['sessions'][-1]['end_reason'] = status
        return result
    result = deepcopy(state)
    result['active']['sync_error'] = status not in ('open',)
    if info.get('name'):
        result['active']['task']['name'] = info['name']
    return result


def sync_lifecycle():
    # Never hold the state lock while waiting on Apple Events; n remains responsive.
    with locked_state() as state:
        active = state.get('active')
        if not active:
            return
        session_id, task_id = active['session_id'], active['task']['id']
    try:
        result = subprocess.run(['/usr/bin/osascript', '-l', 'JavaScript',
                                 str(Path(__file__).with_name('things_timer_status.js')), task_id],
                                capture_output=True, text=True, timeout=3, check=True)
        info = json.loads(result.stdout)
    except (subprocess.SubprocessError, json.JSONDecodeError):
        info = {'status': 'unavailable'}
    with locked_state() as state:
        updated = apply_lifecycle(state, session_id, info, time.time())
        if updated != state:
            save(updated)
        render(updated, time.time())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['toggle', 'finish', 'pause', 'ack', 'tick', 'status', 'show', 'selected', 'sync', 'notice'])
    parser.add_argument('--message', default='')
    parser.add_argument('--task', help='JSON task snapshot from the keyboard watcher')
    args = parser.parse_args()
    # Compatibility for the native p key and old callers; Now owns automatic timing.
    session = Path(__file__).with_name('things_now_session.py')
    if session.exists() and 'THINGS_TIMER_DIR' not in os.environ:
        if args.action == 'show':
            subprocess.run(['/usr/bin/python3',str(Path(__file__).with_name('things_now.py')),'show'],check=True)
        else:
            action = args.action if args.action in ('sync','tick','status','notice') else 'notice'
            command = ['/usr/bin/python3',str(session),action]
            if action == 'notice':
                command += ['--message',args.message or '先编排 · 点击顶栏开始 · 清空后结束']
            subprocess.run(command,check=True)
        return
    action = args.action
    if action == 'sync':
        sync_lifecycle()
        return
    if os.environ.get('SENDER') == 'system_will_sleep':
        action = 'pause'
    task = json.loads(args.task) if args.task else None
    if action == 'selected':
        task, action = selected_task(), 'toggle'
    if task is not None:
        if not isinstance(task.get('id'), str) or not task['id'] or not isinstance(task.get('name'), str):
            raise ValueError('A single valid Things task is required')
        task = {key: task.get(key, '') for key in ('id', 'name', 'project_id', 'project_name')}
    now = time.time()
    with locked_state() as state:
        if action == 'status':
            print(json.dumps({'state': state, 'view': view(state, now)}, ensure_ascii=False))
            return
        if action == 'show':
            active = state.get('active')
            if active:
                from urllib.parse import quote
                subprocess.run(['/usr/bin/open', '-b', 'com.culturedcode.ThingsMac',
                                'things:///show?id=' + quote(active['task']['id'], safe='')], check=True)
            return
        updated = transition(state, action, now, task)
        if action == 'notice':
            updated['notice'] = {'text':args.message, 'expires_at':now+6}
        if updated != state:
            save(updated)
        render(updated, now)


if __name__ == '__main__':
    main()
