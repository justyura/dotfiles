#!/usr/bin/env python3
"""Merge explicit Things selections, backing up originals before any mutation."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import time
import uuid

ROOT=Path.home()/'.local/share/things-merge'

def plan(tasks):
    if len(tasks)<2: raise ValueError('请先选择至少两条任务')
    if any(t.get('status')!='open' for t in tasks): raise ValueError('仅合并未完成任务')
    # Repeating tasks have independent lifecycle rules; do not silently discard those.
    for task in tasks:
        if any(v and ('repeat' in k.lower() or 'recurr' in k.lower()) for k,v in task.items()):
            raise ValueError('重复任务请先取消重复设置再合并')
    tags=[]
    for task in tasks:
        for tag in task.get('tagNames','').split(','):
            if tag.strip() and tag.strip() not in tags: tags.append(tag.strip())
    sections=[]
    for i,task in enumerate(tasks):
        lines=['## '+task['name'],task.get('notes','')]
        if i:
            # Native checklist on the survivor stays intact; source checklists are
            # retained verbatim as structured text, with originals recoverable in Trash.
            for key,value in task.items():
                if 'checklist' in key.lower() and value:
                    lines += ['子清单（原始内容与完成状态）',json.dumps(value,ensure_ascii=False,indent=2)]
            for key in ('when','dueDate','reminderTime','project','area'):
                if task.get(key): lines.append(key+': '+json.dumps(task[key],ensure_ascii=False))
        lines.append('原任务：things:///show?id='+task['id'])
        sections.append('\n\n'.join(x for x in lines if x))
    return {'name':' + '.join(t['name'] for t in tasks),'notes':'\n\n---\n\n'.join(sections),'tags':', '.join(tags)}

def osa(action,request):
    proc=subprocess.run(['/usr/bin/osascript','-l','JavaScript',str(Path(__file__).with_suffix('.js')),action,json.dumps(request,ensure_ascii=False)],capture_output=True,text=True,timeout=30)
    if proc.returncode: raise RuntimeError(proc.stderr.strip())
    return json.loads(proc.stdout)

def notice(message):
    subprocess.run(['/usr/bin/python3',str(Path(__file__).with_name('things_now_session.py')),'notice','--message',message],check=False)

def main():
    p=argparse.ArgumentParser();p.add_argument('--tasks',required=True);p.add_argument('--window',required=True);args=p.parse_args()
    ROOT.mkdir(parents=True,exist_ok=True,mode=0o700)
    with (ROOT/'merge.lock').open('a') as lock:
        try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError: return
        try:
            request={'ids':[x['id'] for x in json.loads(args.tasks)],'window':args.window}
            if len(request['ids'])<2: raise ValueError('请先选择至少两条任务')
            snapshots=osa('snapshot',request)
            request.update(snapshots=snapshots,**plan(snapshots))
            path=ROOT/(time.strftime('%Y%m%d-%H%M%S')+'-'+str(uuid.uuid4())+'.json')
            with path.open('x') as f:
                os.chmod(path,0o600)
                json.dump({'status':'prepared','request':request},f,ensure_ascii=False,indent=2);f.flush();os.fsync(f.fileno())
            result=osa('apply',request)
            # Prepared backup stays immutable, even if recording the result fails.
            path.with_suffix('.result.json').write_text(json.dumps(result,ensure_ascii=False))
            notice(f"已合并 {len(snapshots)} 项 → 1 项")
        except Exception as error:
            notice(str(error)[-140:])
            raise
if __name__=='__main__':main()
