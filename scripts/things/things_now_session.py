#!/usr/bin/env python3
"""Automatic Now batches: fixed wall-clock budget, durable events, local report."""
import argparse
from copy import deepcopy
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

ROOT = Path(os.environ.get('THINGS_NOW_SESSION_DIR', Path.home()/'.local/share/things-now-sessions'))
NOW_ROOT = Path(os.environ.get('THINGS_NOW_DIR', Path.home()/'.local/share/things-now'))
BAR = Path.home()/'.local/bin/focus_bar'


def initial():
    return {'schema':1, 'active':None, 'sessions':[], 'events':[], 'sync_error':False}


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.state-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name): os.unlink(name)


def load():
    path = ROOT/'state.json'
    state = json.loads(path.read_text()) if path.exists() else initial()
    if state.get('schema') != 1: raise ValueError('Unknown Now session schema')
    active = state.get('active')
    if active and 'manual_start' not in active:
        active.update(manual_start=True, planned_at=active['started_at'], previous_auto_started_at=active['started_at'],
                      started_at=None, deadline=None, expired=False)
        event(state, 'timing_corrected', time.time())
        save(ROOT/'state.json', state)
    return state


def event(state, kind, now, **values):
    state['events'].append({'id':str(uuid.uuid4()), 'at':now, 'type':kind,
                            'session_id':state['active']['id'], **values})


def tick(state, now):
    state = deepcopy(state)
    active = state['active']
    if active and active['started_at'] is not None and now >= active['deadline'] and not active['expired']:
        active['expired'] = True
        event(state, 'deadline_reached', active['deadline'])
    return state


def reconcile(state, snapshot, now, budget=3600):
    state = tick(state, now)
    if snapshot is None:
        if not state.get('sync_error') and state['active']:
            event(state, 'sync_unavailable', now)
        state['sync_error'] = True
        return state
    if state.get('sync_error') and state['active']:
        event(state, 'sync_restored', now)
    state['sync_error'] = False
    state['last_sync'] = now
    tasks = snapshot['tasks']
    if not state['active'] and tasks:
        state['active'] = {'id':str(uuid.uuid4()), 'planned_at':now, 'started_at':None, 'deadline':None, 'manual_start':True,
                           'budget':budget, 'expired':False, 'tasks':{}, 'order':[]}
        event(state, 'session_planned', now, budget_seconds=budget)
    active = state['active']
    if not active: return state
    current = {t['id']:t for t in tasks}
    for task_id, task in current.items():
        old = active['tasks'].get(task_id)
        if not old or old['outcome'] != 'open':
            event(state, 'task_added' if not old else 'task_reopened', now, task=task)
        elif any(old['task'].get(k) != task.get(k) for k in ('name','project_id','project_name')):
            event(state, 'task_updated', now, task=task)
        active['tasks'][task_id] = {'task':task, 'outcome':'open'}
    for task_id, item in active['tasks'].items():
        if task_id not in current and item['outcome'] == 'open':
            outcome = snapshot['departed'].get(task_id)
            if outcome not in ('completed','canceled','deleted','removed'):
                # Incomplete reads must never imply completion.
                raise ValueError('Missing authoritative task outcome')
            item.update(outcome=outcome, observed_at=now)
            event(state, 'task_'+outcome, now, task=item['task'])
    active['order'] = list(current)
    if not tasks:
        outcomes = [x['outcome'] for x in active['tasks'].values()]
        reason = 'completed' if all(x == 'completed' for x in outcomes) else 'cleared'
        active.update(ended_at=now, elapsed=max(0,now-active['started_at']) if active['started_at'] is not None else 0, end_reason=reason)
        if active['started_at'] is None: active['end_reason'] = 'not_started'
        event(state, 'session_ended', now, reason=active['end_reason'], elapsed=active['elapsed'])
        state['sessions'].append(active)
        state['active'] = None
    return state


def start(state, now):
    state = deepcopy(state)
    active = state['active']
    if active and active['started_at'] is None and active['order'] and not state.get('sync_error'):
        active.update(started_at=now, deadline=now+active['budget'])
        event(state, 'session_started', now, budget_seconds=active['budget'])
    return state


def clock(seconds):
    minutes, seconds = divmod(max(0,int(seconds)),60)
    return f'{minutes:02d}:{seconds:02d}'


def view(state, now):
    active = state['active']
    if not active:
        last = state['sessions'][-1] if state['sessions'] else None
        status = ('已完成' if last['end_reason']=='completed' else '清单已清空') if last else '待编排'
        remaining = last['budget']-last['elapsed'] if last else 3600
        return {'tasks':f"本轮结束 · 用时 {clock(last['elapsed'])} · n 编排下一轮" if last else 'n 编排任务 · 点击开始后计时',
                'status':'同步待恢复' if state.get('sync_error') else status,
                'clock':('+' if remaining<0 else '')+clock(abs(remaining)),
                'percentage':max(0,min(100,round(100*remaining/(last['budget'] if last else 3600)))),
                'color':'0xff929baa', 'count':'NOW'}
    pending = active['started_at'] is None
    remaining = active['budget'] if pending else active['deadline']-now
    done = sum(x['outcome']=='completed' for x in active['tasks'].values())
    titles = [' '.join(active['tasks'][i]['task']['name'].split()) for i in active['order']]
    return {'tasks':'   ·   '.join(f'{i+1}. {name}' for i,name in enumerate(titles)),
            'status':'同步待恢复' if state.get('sync_error') else ('待开始' if pending else ('超时' if remaining<=0 else '进行中')),
            'clock':('+' if remaining<0 else '')+clock(abs(remaining)),
            'percentage':max(0,min(100,round(100*remaining/active['budget']))),
            'color':'0xfff7768e' if remaining<=0 else ('0xffe0af68' if remaining<600 else '0xff9ece6a'),
            'count':f'NOW {done}/{len(active["tasks"])}'}


def render(state, now):
    if os.environ.get('THINGS_NOW_NO_RENDER')=='1' or not BAR.exists(): return
    data = view(state,now)
    notice = state.get('notice',{})
    status = notice['text'] if now < notice.get('expires_at',0) else data['status']
    values = {'focus.project':{'label':data['count']}, 'focus.task':{'label':data['tasks']},
              'focus.status':{'label':status,'label.color':data['color']},
              'focus.start':{'drawing':'on' if state['active'] and state['active']['started_at'] is None else 'off'},
              'focus.clock':{'label':data['clock'],'label.color':data['color']},
              'focus.progress':{'slider.percentage':str(data['percentage']),'slider.highlight_color':data['color']}}
    path=ROOT/'render.json'
    try: previous=json.loads(path.read_text())
    except (FileNotFoundError,ValueError): previous={}
    args=[]
    for item,props in values.items():
        changed={k:v for k,v in props.items() if previous.get(item,{}).get(k)!=v}
        if changed: args+=['--set',item]+[f'{k}={v}' for k,v in changed.items()]
    if args:
        result=subprocess.run([str(BAR),*args],capture_output=True,timeout=2)
        if result.returncode==0: save(path,values)


def snapshot(state):
    binding=json.loads((NOW_ROOT/'state.json').read_text())
    active=state['active']
    ids=[k for k,v in active['tasks'].items() if v['outcome']=='open'] if active else []
    result=subprocess.run(['/usr/bin/osascript','-l','JavaScript',str(Path(__file__).with_name('things_now_snapshot.js')),
                           binding['tag_id'],json.dumps(ids)],capture_output=True,text=True,timeout=10,check=True)
    value=json.loads(result.stdout)
    if not isinstance(value.get('tasks'),list) or not isinstance(value.get('departed'),dict):
        raise ValueError('Invalid snapshot')
    return value


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action', choices=['sync','start','tick','status','notice','report'])
    parser.add_argument('--message',default='')
    args=parser.parse_args()
    ROOT.mkdir(parents=True,exist_ok=True,mode=0o700)
    if args.action=='report':
        from things_now_report import report
        path=report(ROOT)
        subprocess.run(['/usr/bin/open',str(path)],check=True)
        return
    # Separate sync lock prevents overlapping/out-of-order Apple Event snapshots.
    with (ROOT/'sync.lock').open('a') as sync_lock:
        if args.action in ('sync','start'):
            try: fcntl.flock(sync_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError: return
            with (ROOT/'state.lock').open('a') as lock:
                fcntl.flock(lock,fcntl.LOCK_EX)
                before=load()
            try: info=snapshot(before)
            except (OSError,ValueError,KeyError,subprocess.SubprocessError): info=None
        with (ROOT/'state.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            state=load()
            now=time.time()
            updated=reconcile(state,info,now) if args.action in ('sync','start') else tick(state,now)
            if args.action=='start': updated=start(updated,now)
            if args.action=='notice': updated['notice']={'text':args.message,'expires_at':now+4}
            if updated!=state: save(ROOT/'state.json',updated)
            if args.action=='status': print(json.dumps({'state':updated,'view':view(updated,now)},ensure_ascii=False))
            render(updated,now)
        if args.action in ('sync','start'):
            # Portable report contains the event stream and left-bar timeline.
            from things_now_report import report
            cache=ROOT/'report.stamp'
            if len(updated['events'])!=len(state['events']) or not cache.exists() or now-cache.stat().st_mtime>=60:
                report(ROOT)
                cache.touch()

if __name__=='__main__': main()
