#!/usr/bin/env bash
# 在 nvim 里写一条任务，投递进与当前 tmux session 同名的 Things 项目。
# 第一行 = 标题，其余行 = notes；单独成行的 --- 开启下一条任务。
# 行首序号（1. 1、 1) 1））也开启下一条任务，序号后面的文字就是标题：
#   1. 写文档 / 2. 改 bug 换行写成两行 = 两条任务；序号后不跟数字，所以 "3.5 斤" 不会被当成序号。
# 项目不存在时自动创建，放进 DEFAULT_AREA。
#
#   things_capture.sh <session> <text...>
#   things_capture.sh --edit                   # 开 nvim 输入（用于 display-popup）
#   things_capture.sh --edit --quick-entry     # 改为弹 Things Quick Entry 面板
set -euo pipefail

DEFAULT_AREA="Personal"

QUICK_ENTRY=0
EDIT=0
JOB=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick-entry) QUICK_ENTRY=1; shift ;;
        --edit)        EDIT=1;        shift ;;
        --deliver)     JOB="$2";      shift 2 ;;
        *) break ;;
    esac
done

# 投递跑在后台、stdout 被丢弃，所以失败必须走状态栏，否则你根本看不见
die() {
    echo "things_capture: $*" >&2
    [[ -n "${TMUX:-}" ]] && tmux display-message "Things 采集失败: $*"
    exit 1
}

if (( EDIT )); then
    SESSION=$(tmux display-message -p '#{session_name}')
    BUF=$(mktemp -t things_capture)
    trap 'rm -f "$BUF"' EXIT

    # 空文件进、空文件出 = 取消：:q 不写盘，所以读到的仍是空。
    # 两个 cnoreabbrev：:q -> :q! 免得改过 buffer 后报 E37；:w -> :wq 让「保存」
    # 直接等于「提交」。都不影响 :wq —— 那是一个词，abbrev 只认独立的 q / w。
    # 不映射 <Esc>：vim 里习惯性连按 Esc 确认普通模式，映射成退出会吞掉已写的内容。
    nvim \
        -c 'setlocal filetype=markdown' \
        -c 'set laststatus=2' \
        -c "setlocal statusline=\ Things\ →\ ${SESSION//[^A-Za-z0-9_.-]/}%=首行=标题\ 其余=notes\ \ 1./---\ 分条\ \ │\ \ :w\ 提交\ \ :q\ 取消\ " \
        -c 'cnoreabbrev q q!' \
        -c 'cnoreabbrev w wq' \
        -c 'startinsert' \
        "$BUF"

    CONTENT=$(cat "$BUF")
    [[ -z "${CONTENT//[[:space:]]/}" ]] && exit 0

    # 投递要拉起 Things、跑 osascript、发 URL，都是几百毫秒级的阻塞，不能留在前台。
    # 但也不能只靠 fork：popup 一关，tmux 会把它自己那个进程组整个端掉，
    # 后台子进程会在跑完之前被杀。交给 tmux server 执行才与 popup 的生死无关。
    # 内容走文件不走 argv：run-shell 的命令串要过一层 sh -c，引号会再被解析一次。
    JOB=$(mktemp -t things_capture_job)
    { printf '%s\n' "$SESSION"; printf '%s' "$CONTENT"; } > "$JOB"
    CMD=$(printf '%q %q %q' "$0" --deliver "$JOB")
    (( QUICK_ENTRY )) && CMD="$CMD --quick-entry"
    tmux run-shell -b "$CMD"
    exit 0
elif [[ -n "$JOB" ]]; then
    SESSION=$(head -n 1 "$JOB")
    CONTENT=$(tail -n +2 "$JOB")
    rm -f "$JOB"
else
    SESSION="${1:-}"
    shift || true
    CONTENT="$*"
fi

[[ -z "${CONTENT//[[:space:]]/}" ]] && exit 0

# 后台拉起 Things（-g 不抢焦点，-j 保持隐藏），否则 osascript 会把它弹到前台
open -gj -a Things3 2>/dev/null || die "无法启动 Things3"

# 读：所有未完成项目的 id 与名字。
# 这一步失败（多半是自动化权限被拒）必须中止——否则查不到已有项目，
# 每次采集都会新建一个重名项目。
if ! PROJECTS=$(osascript <<'END' 2>&1
tell application "Things3"
    set out to ""
    repeat with p in projects
        if status of p is open then
            set out to out & (id of p) & tab & (name of p) & linefeed
        end if
    end repeat
    return out
end tell
END
); then
    die "读取 Things 项目失败（检查 系统设置 → 隐私与安全性 → 自动化）: $PROJECTS"
fi

# 匹配 + 拼 URL：归一化抵消 tmux-sessionizer 的 tr ".,: " "____"
RESULT=$(SESSION="$SESSION" CONTENT="$CONTENT" AREA="$DEFAULT_AREA" QE="$QUICK_ENTRY" \
         PROJECTS="$PROJECTS" python3 <<'END'
import json, os, re
from urllib.parse import quote

norm = lambda s: re.sub(r"[._,: -]+", "_", s.strip().lower())
q = lambda s: quote(s, safe="")

env = os.environ
session, area, qe = env["SESSION"], env["AREA"], env["QE"] == "1"

# 单独成行的 --- 开启下一条任务；每段内部再按行首序号（1. 1、 1) 1））继续分条，
# 分完每条仍是「首行=标题，其余=notes」
# 序号后面不能跟数字，否则 "3.5 斤苹果" 这种会被当成序号切坏
MARKER = re.compile(r"^[ \t]*\d{1,2}[.．、)）][ \t]*(?!\d)")

def by_number(block):
    chunks, cur = [], []
    for line in block.splitlines():
        m = MARKER.match(line)
        if m:
            if cur:
                chunks.append(cur)
            cur = [line[m.end():]]       # 序号本身不进标题
        else:
            cur.append(line)
    if cur:
        chunks.append(cur)
    return chunks

tasks = []
for block in re.split(r"(?m)^[ \t]*-{3,}[ \t]*$", env["CONTENT"]):
    for lines in by_number(block):
        while lines and not lines[0].strip():
            lines.pop(0)
        if not lines:
            continue
        title = lines[0].strip()
        notes = "\n".join(lines[1:]).strip()
        if not title and not notes:
            continue
        task = {"title": title}
        if notes:
            task["notes"] = notes
        tasks.append(task)

if not tasks:
    print("empty\t")
    raise SystemExit

pid = None
for line in env["PROJECTS"].splitlines():
    if "\t" in line:
        i, name = line.split("\t", 1)
        if norm(name) == norm(session):
            pid = i
            break

if qe and len(tasks) == 1:
    # 面板是交互式的，在它背后偷偷建项目会很意外：项目不存在就只填名字，
    # 由你在面板里自己决定。
    t = tasks[0]
    url = f"things:///add?show-quick-entry=true&title={q(t['title'])}"
    url += f"&list-id={q(pid)}" if pid else f"&list={q(session)}"
    if "notes" in t:
        url += f"&notes={q(t['notes'])}"
    status = "quick-entry"
else:
    # 一律走 json：add?titles= 虽然能一次多条，但给不了每条各自的 notes。
    # 纯 create 不需要 auth-token。
    if pid:
        payload = [{"type": "to-do", "attributes": dict(t, **{"list-id": pid})}
                   for t in tasks]
        status = "existing"
    else:
        payload = [{
            "type": "project",
            "attributes": {
                "title": session,
                "area": area,
                "items": [{"type": "to-do", "attributes": t} for t in tasks],
            },
        }]
        status = "created"
    url = "things:///json?data=" + q(json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    # Quick Entry 一次只能承载一条，多条时退回静默投递
    if qe:
        status += "-multi"

print(f"{status}\t{url}\t{len(tasks)}")
END
)

IFS=$'\t' read -r STATUS URL COUNT <<<"$RESULT"

# 内容全是分隔符/空行，没解析出任何任务
[[ "$STATUS" == empty ]] && exit 0

if [[ "$STATUS" == quick-entry ]]; then
    open "$URL"          # 面板需要焦点
else
    open -g "$URL"       # 静默投递，不打断
fi

if [[ -n "${TMUX:-}" ]]; then
    if (( COUNT == 1 )); then
        LABEL=$(printf '%s' "$CONTENT" | sed '/^[[:space:]]*$/d' | head -1)
    else
        LABEL="$COUNT 条任务"
    fi
    case "$STATUS" in
        created)  tmux display-message "Things: 新建项目 $SESSION ← $LABEL" ;;
        existing) tmux display-message "Things: $SESSION ← $LABEL" ;;
        *-multi)  tmux display-message "Things: 多条不支持 Quick Entry，已静默投递 $LABEL 到 $SESSION" ;;
    esac
fi
