#!/bin/bash
# Tap right Option: summon Things; Escape hides it without Dock animations. Queue rapid key presses.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
YABAI=/opt/homebrew/bin/yabai
JQ=/opt/homebrew/bin/jq
state="${TMPDIR:-/tmp}/things_native_${UID}"
mkdir -p "$state" || exit 1
if [ "${THINGS_SUMMON_LOCKED:-}" != 1 ]; then
    exec /usr/bin/python3 "$HOME/.config/scripts/things/things_summon.py" "$0" "$@"
fi
visibility="$HOME/.config/scripts/things/things_visibility"
if [ ! -x "$visibility" ] || [ "$visibility.swift" -nt "$visibility" ]; then
    swiftc -module-cache-path "$state/module-cache" -O "$visibility.swift" -o "$visibility" || exit 1
fi

focused=$("$YABAI" -m query --windows --window 2>/dev/null)
space=$("$YABAI" -m query --spaces --space | "$JQ" -er '.index') || exit 1
app=$(printf '%s' "$focused" | "$JQ" -r '.app // empty')
window=$("$YABAI" -m query --windows | "$JQ" -c '[.[] | select(.app == "Things" and .subrole == "AXStandardWindow")][0] // empty')
/bin/bash "$HOME/.config/scripts/things/things_escape.sh" --start
# Escape hides the foreground Things app; right Option only summons it.
if [ "${1:-}" = --hide ]; then
    [ "$app" = Things ] || exit 0
    restore_previous=false
    if [ -f "$state/shown" ] && [ "$(cat "$state/shown")" = "$space" ]; then
        restore_previous=true
    fi
    "$visibility" hide || exit 1
    rm -f "$state/shown"
    if $restore_previous && read -r previous < "$state/previous"; then
        previous_space=$("$YABAI" -m query --windows --window "$previous" 2>/dev/null | "$JQ" -r '.space // empty')
        if [ "$previous_space" = "$space" ]; then
            "$YABAI" -m window --focus "$previous" 2>/dev/null || true
        fi
    fi
    exit 0
fi
# Repeated Option still raises the current list; an active app can have a covered window.
if [ "$app" = Things ] && [ -z "${1:-}" ] && [ -n "$window" ]; then
    wid=$(printf '%s' "$window" | "$JQ" -er '.id') || exit 1
    exec /bin/bash "$HOME/.config/scripts/things/things_front.sh" "$wid" "$space"
fi

if [ "$app" != Things ]; then
    printf '%s' "$focused" | "$JQ" -r '.id // empty' > "$state/previous"
fi
# Capture Canvas context before activating Things. Explicit task IDs keep priority.
canvas_project_id=""
if [[ "${1:-}" = tag:* ]]; then
    canvas_project_id="$1"
    project="$1"
    set --
elif [[ "${1:-}" = project:* ]]; then
    canvas_project_id="${1#project:}"
    project="canvas:$canvas_project_id"
    set --
elif [ "$app" = InfiniteCanvas ] && [ -z "${1:-}" ]; then
    source_pid=$(printf '%s' "$focused" | "$JQ" -er '.pid') || exit 1
    if ! canvas_project_id=$(/usr/bin/python3 "$HOME/.config/scripts/things/infinitecanvas_context.py" resolve --pid "$source_pid" 2> "$state/context-error"); then
        osascript - "$(cat "$state/context-error")" <<'CONTEXT_ERROR'
on run argv
    display notification (item 1 of argv) with title "Infinite Canvas → Things"
end run
CONTEXT_ERROR
        exit 1
    fi
    project="canvas:$canvas_project_id"
elif [ "$app" = Safari ]; then
    project=Safari
else
    project=$(tmux list-clients -F '#{client_activity} #{session_name}' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
fi
"$HOME/.config/scripts/things/things_nav.sh" exit_mode
if [ -z "$window" ] || ! "$visibility" status >/dev/null 2>&1; then
    # LaunchServices sends reopen even when Things is running with no windows.
    /usr/bin/open -g -b com.culturedcode.ThingsMac || exit 1
fi
for ((attempt=0; attempt<30; attempt++)); do
    [ -n "$window" ] && break
    window=$("$YABAI" -m query --windows | "$JQ" -c '[.[] | select(.app == "Things" and .subrole == "AXStandardWindow")][0] // empty')
    [ -n "$window" ] && break
    sleep 0.1
done
[ -n "$window" ] || exit 1
wid=$(printf '%s' "$window" | "$JQ" -r '.id')
# macOS can restore a hidden window to its old Space on unhide. Unhide first,
# then move the real window; never move a hidden window and activate afterward.
"$visibility" unhide || exit 1
for ((attempt=0; attempt<30; attempt++)); do
    window=$("$YABAI" -m query --windows --window "$wid")
    [ "$(printf '%s' "$window" | "$JQ" -r '."is-hidden"')" = false ] && break
    sleep 0.01
done
if [ "$(printf '%s' "$window" | "$JQ" -r '."is-minimized"')" = true ]; then
    "$YABAI" -m window --deminimize "$wid" || exit 1
fi
if [ "$(printf '%s' "$window" | "$JQ" -r '."is-floating"')" != true ]; then
    "$YABAI" -m window "$wid" --toggle float || exit 1
fi
if [ "$(printf '%s' "$window" | "$JQ" -r '."is-sticky"')" = true ]; then
    "$YABAI" -m window "$wid" --toggle sticky || exit 1
fi
display=$("$YABAI" -m query --displays --display | "$JQ" -er '.index') || exit 1
if [ "$(printf '%s' "$window" | "$JQ" -r '.space')" != "$space" ]; then
    "$YABAI" -m window "$wid" --space "$space" || exit 1
fi
if [ "$(cat "$state/window" 2>/dev/null)" != "$wid:display:$display" ]; then
    "$YABAI" -m window "$wid" --grid 10:10:2:1:6:8 || exit 1
    printf '%s\n' "$wid:display:$display" > "$state/window"
fi
# Only resolve the project when context changes, not on every toggle.
if [ -n "${1:-}" ] || [ "$(cat "$state/project" 2>/dev/null)" != "$wid:$project" ] ||
    [ "$(printf '%s' "$window" | "$JQ" -r '.title')" != "$project" ]; then
osascript - "$project" "${1:-}" "$canvas_project_id" <<'APPLESCRIPT'
on run argv
    tell application "Things3"
        if item 2 of argv is not "" then
            show to do id (item 2 of argv)
        else if item 3 of argv starts with "tag:" then
            do shell script "/usr/bin/open -g -b com.culturedcode.ThingsMac " & quoted form of ("things:///show?id=" & text 5 thru -1 of (item 3 of argv))
        else if item 3 of argv is not "" then
            show project id (item 3 of argv)
        else if item 1 of argv is not "" then
            set matches to projects whose name is (item 1 of argv) and status is open
            if (count of matches) > 0 then show item 1 of matches
        end if
    end tell
end run
APPLESCRIPT
    if [ "$?" -eq 0 ] && [ -z "${1:-}" ]; then
        printf '%s\n' "$wid:$project" > "$state/project"
    else
        rm -f "$state/project"
    fi
fi
# Retry raising/focusing within the same keypress, including a cold-started window.
if /bin/bash "$HOME/.config/scripts/things/things_front.sh" "$wid" "$space" "$canvas_project_id"; then
    printf '%s\n' "$space" > "$state/shown"
    exit 0
fi
rm -f "$state/shown"
exit 1
