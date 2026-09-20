#!/usr/bin/env python3
"""Portable task-session report, alongside the existing activity timeline."""
import datetime as dt
import html
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import time

LABELS={'session_planned':'编排待开始','timing_corrected':'撤销自动开工计时，等待手动开始','session_started':'开始工作时段','task_added':'加入 Now','task_reopened':'重新加入',
        'task_updated':'任务更新','task_completed':'完成','task_canceled':'取消','task_deleted':'删除',
        'task_removed':'移出 Now','deadline_reached':'到达时间预算','session_ended':'结束工作时段',
        'sync_unavailable':'Things 同步中断','sync_restored':'Things 同步恢复'}

def atomic(path,text):
    fd,tmp=tempfile.mkstemp(prefix='.report-',dir=path.parent)
    with os.fdopen(fd,'w') as f: f.write(text)
    os.replace(tmp,path)

def report(root, activity_source=None):
    root=Path(root)
    root.mkdir(parents=True,exist_ok=True)
    path=root/'state.json'
    state=json.loads(path.read_text()) if path.exists() else {'active':None,'sessions':[],'events':[]}
    now=time.time()
    esc=lambda x:html.escape(str(x))
    clock=lambda x:dt.datetime.fromtimestamp(x).strftime('%m-%d %H:%M:%S')
    active=state['active']
    sessions=([active] if active else [])+list(reversed(state['sessions']))
    cards=[]
    for s in sessions:
        finished=s.get('ended_at')
        duration=max(0,(finished or now)-s['started_at']) if s['started_at'] is not None else 0
        done=sum(x['outcome']=='completed' for x in s['tasks'].values())
        label=('全部完成' if s.get('end_reason')=='completed' else '清单已清空') if finished else ('超时进行中' if s['deadline'] is not None and now>=s['deadline'] else '进行中')
        if s['started_at'] is None: label='未开始即清空' if finished else '待开始'
        names=''.join('<li>'+esc(x['task']['name'])+' <small>'+esc({'open':'待办','completed':'已完成','canceled':'已取消','deleted':'已删除','removed':'已移出'}[x['outcome']])+'</small></li>' for x in s['tasks'].values())
        rows=[]
        for e in state['events']:
            if e['session_id']==s['id']:
                rows.append('<tr><td>'+clock(e['at'])+'</td><td>'+LABELS.get(e['type'],esc(e['type']))+'</td><td>'+esc(e.get('task',{}).get('name',''))+'</td></tr>')
        cards.append(f'<section><div class="eyebrow">{clock(s["started_at"] or s.get("planned_at",now))} → {clock(finished) if finished else "现在"}</div><h2>{label} <small>{done}/{len(s["tasks"])} 完成</small></h2><p>用时 {duration/60:.1f} 分钟 / 预算 {s["budget"]/60:.0f} 分钟 · 超时 {max(0,duration-s["budget"])/60:.1f} 分钟</p><progress max="{len(s["tasks"]) or 1}" value="{done}"></progress><ul>{names}</ul><details><summary>任务事件日志</summary><table>{"".join(rows)}</table></details></section>')
    activity_source=Path(activity_source or Path.home()/'.config/scripts/sketchybar/activity_history.py')
    activity=''
    if activity_source.exists():
        spec=importlib.util.spec_from_file_location('now_activity_history',activity_source)
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        timeline=module.report()
        atomic(root/'activity.html',timeline.read_text())
        activity='<section><h2>工作与休息时间线</h2><p>沿用左栏记录。操作、在场、休息状态与任务完成分别呈现；不推算单项任务专注时长。</p><iframe title="每日活动时间线" src="activity.html"></iframe></section>'
    atomic(root/'events.jsonl',''.join(json.dumps(e,ensure_ascii=False)+'\n' for e in state['events']))
    atomic(root/'report.json',json.dumps({'schema':1,'generated_at':now,'timezone':str(dt.datetime.now().astimezone().tzinfo),**state},ensure_ascii=False))
    page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="60"><title>Now · 工作报告</title><style>
:root{color-scheme:dark}body{margin:48px auto;padding:0 24px;max-width:1100px;background:#14191f;color:#e0e6ee;font:15px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.65}h1{font-size:36px;letter-spacing:-1px;margin-bottom:6px}h2{font-size:21px;margin:8px 0}p,small,.eyebrow{color:#96a5b5}small{font-weight:400;margin-left:12px;font-size:13px}section{background:#1b222c;border:1px solid #2b3542;border-radius:14px;padding:24px;margin:24px 0}a{color:#9eceb0}nav{display:flex;gap:22px}progress{width:100%;height:7px;accent-color:#9ece6a}li{padding:4px 0;overflow-wrap:anywhere}table{width:100%;border-collapse:collapse;font-size:13px}td{padding:9px;border-bottom:1px solid #303846;overflow-wrap:anywhere}summary{cursor:pointer;color:#9eceb0}iframe{border:0;width:100%;height:650px;border-radius:8px}.eyebrow{font-size:12px;font-family:monospace}@media(max-width:600px){body{padding:0 14px;margin:24px auto}section{padding:16px}td{padding:5px}}
</style><h1>Now · 工作报告</h1><p>把计划放进时间边界里。先编排，点击开始后计时；清单清空时结束。</p><nav><a href="#sessions">工作时段</a><a href="report.json">完整数据 JSON</a><a href="events.jsonl">事件日志</a></nav>'''
    page+=f'<p>更新于 {clock(now)} · 每分钟刷新。时间预算按自然时间计算，包含休息与睡眠。任务事件时间为本机观察到变化的时间。</p><div id="sessions">'+(''.join(cards) or '<section>Now 加入第一条待办后，这里会自动记录工作时段。</section>')+'</div>'+activity+'</html>'
    atomic(root/'report.html',page)
    return root/'report.html'
