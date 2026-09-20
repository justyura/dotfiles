#!/usr/bin/env python3
"""Prospective local observations, never keys, app names or camera frames."""
import datetime as dt
import html
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path.home() / '.local/share/sketchybar/activity'
STATES = {'manual_break': ('主动休息', '#76c7bd'), 'active': ('操作', '#b7d69a'), 'present': ('在场 · 未操作', '#88b5d4'),
          'idle': ('空闲 · 待确认', '#b5a3ce'), 'away': ('疑似离开', '#c3a374'),
          'locked': ('锁屏', '#67748d'), 'unknown': ('未知 / 休眠间隔', '#343b49')}


def classify(activity, presence, now, threshold, ttl):
    if activity.get('manual_break'):
        return 'manual_break'
    if activity.get('unavailable'):
        return 'unknown'
    if activity.get('locked'):
        return 'locked'
    if activity.get('idle', threshold) < 15:
        return 'active'
    fresh = 0 <= now - presence.get('at', 0) <= ttl
    if fresh and presence.get('status') == 'present':
        return 'present'
    if activity.get('idle', threshold) < threshold:
        return 'idle'
    if fresh and presence.get('status') == 'absent':
        return 'away'
    return 'unknown'


def record(now, activity, presence, threshold, ttl, root=ROOT):
    root.mkdir(parents=True, exist_ok=True)
    day = dt.datetime.fromtimestamp(now).date().isoformat()
    row = {'at': round(now, 3), 'state': classify(activity, presence, now, threshold, ttl),
           'idle': round(activity.get('idle', 0), 1), 'locked': activity.get('locked'),
           'camera': presence.get('status', 'unavailable'), 'camera_at': presence.get('at')}
    with (root / f'{day}.jsonl').open('a') as f:
        f.write(json.dumps(row, separators=(',', ':')) + '\n')


def segments(rows, start, end):
    """Only extend an observation to the next sample, at most 30 seconds."""
    result = []
    def add(a, b, state):
        if b <= a:
            return
        if result and result[-1][2] == state and result[-1][1] == a:
            result[-1] = (result[-1][0], b, state)
        else:
            result.append((a, b, state))
    cursor = start
    for i, row in enumerate(rows):
        a = max(start, row['at'], cursor)
        if a >= end:
            break
        add(cursor, a, 'unknown')
        nxt = rows[i+1]['at'] if i+1 < len(rows) else end
        b = min(end, nxt, row['at'] + 30)
        add(a, b, row['state'] if row['state'] in STATES else 'unknown')
        cursor = max(a, b)
    add(cursor, end, 'unknown')
    return result


def report(root=ROOT):
    now = dt.datetime.now().timestamp()
    days = []
    for path in sorted(root.glob('????-??-??.jsonl'), reverse=True):
        date = dt.date.fromisoformat(path.stem)
        start = dt.datetime.combine(date, dt.time()).timestamp()
        end = dt.datetime.combine(date + dt.timedelta(days=1), dt.time()).timestamp()
        rows = []
        for line in path.read_text().splitlines():
            try:
                row = json.loads(line)
                if isinstance(row.get('at'), (float, int)) and 'state' in row:
                    rows.append(row)
            except ValueError:
                continue  # a crash or concurrent append may leave a partial last row
        rows.sort(key=lambda r: r['at'])
        parts = segments(rows, start, min(now, end))
        bars, detail = [], []
        totals = {s: 0 for s in STATES}
        for a, b, state in parts:
            totals[state] += b - a
            label, color = STATES[state]
            clock = lambda t: dt.datetime.fromtimestamp(t).strftime('%H:%M:%S')
            title = f'{clock(a)} – {clock(b)} · {label}'
            bars.append(f'<span title="{title}" style="left:{100*(a-start)/(end-start):.5f}%;width:{100*(b-a)/(end-start):.5f}%;background:{color}"></span>')
            detail.append(f'<tr><td>{clock(a)} – {clock(b)}</td><td>{label}</td><td>{(b-a)/60:.1f} 分</td></tr>')
        summary = ' · '.join(f'{STATES[s][0]} {totals[s]/60:.0f} 分' for s in ('active','present','manual_break','away','locked'))
        days.append(f'<section><h2>{html.escape(path.stem)}</h2><p>{summary}</p><div class="line">{"".join(bars)}</div><div class="axis"><span>00:00</span><span>06:00</span><span>12:00</span><span>18:00</span><span>24:00</span></div><details><summary>查看时间段</summary><table>{"".join(detail)}</table></details></section>')
    legend = ''.join(f'<span><i style="background:{c}"></i>{label}</span>' for label,c in STATES.values())
    page = '''<!doctype html><html lang="zh"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>每日活动时间线</title><style>
body{background:#171b22;color:#dce2eb;font:15px -apple-system,sans-serif;max-width:1040px;margin:64px auto;padding:0 28px}h1{font-size:28px}h2{font-size:18px}p,.axis{color:#98a5b7;line-height:1.7}section{margin:38px 0;padding-top:16px;border-top:1px solid #303846}.line{position:relative;height:30px;background:#232a35;border-radius:6px;overflow:hidden}.line span{position:absolute;height:100%}.axis{display:flex;justify-content:space-between;font-size:12px;margin-top:8px}.legend{display:flex;flex-wrap:wrap;gap:18px;font-size:13px}i{display:inline-block;width:9px;height:9px;border-radius:3px;margin-right:7px}summary{cursor:pointer;color:#a9bbd0;margin-top:18px}table{width:100%;font-size:13px;border-collapse:collapse}td{padding:8px;border-bottom:1px solid #262e3a}
</style><h1>每日活动时间线</h1><p>只记录本机状态与时间，不保存按键内容或照片。约每 5 秒采样；摄像头仅辅助判断有人在场，并不识别坐姿。空闲不等于离开，休眠或未记录区间标为未知。重新从菜单打开可更新数据。</p>'''
    root.mkdir(parents=True, exist_ok=True)
    output = root / 'timeline.html'
    output.write_text(page + f'<div class="legend">{legend}</div>' + ''.join(days) + ('<p>开始记录后会显示时间线。</p>' if not days else '') + '</html>')
    return output


if __name__ == '__main__':
    path = report()
    if '--open' in sys.argv:
        subprocess.run(['/usr/bin/open', str(path)], check=True)
    print(path)
