#!/usr/bin/env python3
"""Arrange selected tasks using an ID-bound Now tag, preserving their projects."""
import argparse
import shutil
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(os.environ.get('THINGS_NOW_DIR', Path.home() / '.local/share/things-now'))

def save(state):
    fd, name = tempfile.mkstemp(prefix='.state-', dir=ROOT)
    with os.fdopen(fd, 'w') as file:
        json.dump(state, file, ensure_ascii=False)
        file.flush()
        os.fsync(file.fileno())
    os.replace(name, ROOT / 'state.json')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('action',choices=['ensure','enqueue','show','migrate'])
    parser.add_argument('--tasks',default='[]')
    args=parser.parse_args()
    tasks=json.loads(args.tasks)
    if not isinstance(tasks,list) or any(not isinstance(t.get('id'),str) or not t['id'] for t in tasks):
        raise ValueError('Expected selected task IDs')
    ROOT.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (ROOT/'state.lock').open('a') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: return
        path=ROOT/'state.json'
        state=json.loads(path.read_text()) if path.exists() else {'schema':1,'project_id':'','origins':{}}
        if state.get('schema') == 1:
            if path.exists() and not (ROOT/'state.before-tags.json').exists():
                shutil.copy2(path, ROOT/'state.before-tags.json')
            state.update(schema=2, legacy_project_id=state.pop('project_id', ''), tag_id='')
        if state.get('schema') != 2: raise ValueError('Unknown Now state schema')
        if args.action == 'migrate': tasks=list(state.get('origins', {}).values())
        save(state)
        result=subprocess.run(['/usr/bin/osascript','-l','JavaScript',str(Path(__file__).with_suffix('.js')),
                               'ensure' if args.action == 'show' else args.action,state['tag_id'],json.dumps(tasks,ensure_ascii=False),state.get('legacy_project_id','')],
                              capture_output=True,text=True,timeout=30,check=True)
        result=json.loads(result.stdout)
        state['tag_id']=result['tag_id']
        state['last_result']=result
        save(state)
        if args.action == 'show':
            subprocess.run(['/bin/bash',str(Path(__file__).with_name('toggle_things.sh')), 'tag:' + state['tag_id']],check=True)
        print(json.dumps(result,ensure_ascii=False))
        if args.action == 'enqueue':
            message=f"已编排 {len(result['added']) + len(result['already'])} 项 · Now"
            if result['skipped']: message += f" · 跳过 {len(result['skipped'])} 项"
            subprocess.run(['/usr/bin/python3', str(Path(__file__).with_name('things_timer.py')), 'notice', '--message', message], check=False)
        if result['errors']: raise RuntimeError('Some tasks could not be arranged; see last_result in Now state')

if __name__=='__main__':main()
