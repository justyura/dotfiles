#!/usr/bin/python3
"""Read Canvas context, bind Things projects, or open project-aware Quick Entry."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import parse_qs, urlencode, urlparse
from uuid import UUID

BUNDLE = "com.yura.infinitecanvas2026"
HOME = Path.home()
CONTEXT_PATHS = [
    HOME / "Library/Containers" / BUNDLE / "Data/Library/Application Support/InfiniteCanvas/Automation/current-project.json",
    HOME / "Library/Application Support/InfiniteCanvas/Automation/current-project.json",
]
MAPPING_PATH = HOME / ".config/things/infinitecanvas-projects.json"


def run(args, **kwargs):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def front_window():
    return json.loads(run(["/opt/homebrew/bin/yabai", "-m", "query", "--windows", "--window"]))


def context_paths():
    # Recent macOS releases may name sandbox containers with UUIDs rather than bundle IDs.
    # Only inspect our exact contract filename, then verify embedded bundle ID and source PID.
    return CONTEXT_PATHS + list((HOME / "Library/Containers").glob(
        "*/Data/Library/Application Support/InfiniteCanvas/Automation/current-project.json"))


def read_context(pid, paths=None):
    for path in paths if paths is not None else context_paths():
        try:
            value = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if not isinstance(value, dict):
            continue
        if value.get("schemaVersion") != 1 or value.get("bundleIdentifier") != BUNDLE:
            continue
        if value.get("pid") != pid:
            continue
        # The source process must still exist; old files survive normal exit and crashes.
        os.kill(pid, 0)
        project = value.get("project")
        if value.get("view") in ("home", "reader") and project is None:
            return value
        if value.get("view") not in ("canvas", "preview") or not isinstance(project, dict):
            raise ValueError("项目上下文格式无效。")
        UUID(project["id"])
        if not isinstance(project.get("name"), str):
            raise ValueError("当前项目名称无效。")
        return value
    raise ValueError("没有找到当前进程的项目上下文，请启动更新后的 Infinite Canvas 并进入项目。")


def save_mapping(mapping, path=None):
    path = path or MAPPING_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".infinitecanvas-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(mapping, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_mapping():
    if not MAPPING_PATH.exists():
        return {}
    result = json.loads(MAPPING_PATH.read_text())
    if not isinstance(result, dict):
        raise ValueError("Things 项目映射必须是 JSON 对象。")
    return result


RESOLVE_SCRIPT = '''on run argv
    tell application "Things3"
        if item 1 of argv is not "" then
            set matches to projects whose id is (item 1 of argv) and status is open
        else
            set matches to projects whose name is (item 2 of argv) and status is open
        end if
        if (count of matches) is 0 and item 1 of argv is "" and item 3 of argv is "create" then
            set createdProject to make new project with properties {name:(item 2 of argv)}
            return id of createdProject
        end if
        if (count of matches) is not 1 then
            error "未找到唯一的开放 Things 项目；请用 bind 指定项目链接。"
        end if
        return id of item 1 of matches
    end tell
end run
'''


def require_project(project):
    if project is None:
        raise ValueError("当前画布界面没有项目，请先进入一个 Project。")
    return project


@contextmanager
def mapping_lock():
    # Serialize create+bind across Option and Quick Entry, using a separate lock inode.
    MAPPING_PATH.parent.mkdir(parents=True, exist_ok=True)
    with MAPPING_PATH.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def things_project_name(project):
    name = project["name"].strip()
    if name.lower() in ("", "新项目", "未命名", "untitled", "new project"):
        return f"{name or '新项目'} · {str(UUID(project['id']))[:8]}"
    return name


def resolve(project):
    project = require_project(project)
    with mapping_lock():
        return resolve_locked(project)


def resolve_locked(project):
    mapping = load_mapping()
    key = str(UUID(project["id"]))
    bound = mapping.get(key, "")
    if not isinstance(bound, str):
        raise ValueError("Things 项目映射的值必须是项目 ID。")
    things_id = run(["/usr/bin/osascript", "-", bound, things_project_name(project), "create"], input=RESOLVE_SCRIPT)
    if not things_id:
        raise ValueError("Things 返回了空项目 ID。")
    if not bound:
        mapping[key] = things_id
        save_mapping(mapping)
    return things_id


def quick_entry_url(things_id, title=""):
    return "things:///add?" + urlencode({"list-id": things_id, "show-quick-entry": "true", "title": title})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["context", "resolve", "quick-add", "bind"])
    parser.add_argument("--pid", type=int, help="PID captured from the source window before Things activates")
    parser.add_argument("--project", help="Canvas UUID for bind (otherwise use foreground Canvas)")
    parser.add_argument("--things", help="Things project ID or copied things:///show?id=... link")
    parser.add_argument("--title", default="", help="Optional Quick Entry title")
    args = parser.parse_args()
    try:
        if args.command == "bind" and args.project:
            project = {"id": str(UUID(args.project)), "name": ""}
        else:
            pid = args.pid
            if pid is None:
                window = front_window()
                if window.get("app") != "InfiniteCanvas":
                    raise ValueError("请先聚焦 Infinite Canvas 项目窗口。")
                pid = window["pid"]
            if not isinstance(pid, int) or pid <= 0:
                raise ValueError("来源进程无效。")
            context = read_context(pid)
            project = context["project"]
        if args.command == "context":
            print(json.dumps(context, ensure_ascii=False, indent=2))
        elif args.command == "bind":
            project = require_project(project)
            if not args.things:
                raise ValueError("bind 需要 --things 项目 ID 或项目链接。")
            things_id = args.things
            if things_id.startswith("things:"):
                things_id = parse_qs(urlparse(things_id).query).get("id", [""])[0]
            if not things_id:
                raise ValueError("Things 链接缺少项目 ID。")
            # Verify it is an open project, not a task or area, before persisting.
            things_id = run(["/usr/bin/osascript", "-", things_id, "", "verify"], input=RESOLVE_SCRIPT)
            with mapping_lock():
                mapping = load_mapping()
                mapping[str(UUID(project["id"]))] = things_id
                save_mapping(mapping)
            print(things_id)
        else:
            things_id = resolve(project)
            if args.command == "resolve":
                print(things_id)
            else:
                run(["/usr/bin/open", "-b", "com.culturedcode.ThingsMac", quick_entry_url(things_id, args.title)])
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        message = error.stderr.strip() if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(message, file=sys.stderr)
        if args.command == "quick-add":
            subprocess.run(["/usr/bin/osascript", "-", message], input='''on run argv
                display notification (item 1 of argv) with title "Infinite Canvas → Things"
            end run''', text=True, capture_output=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
