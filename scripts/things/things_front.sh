#!/bin/bash
# Bring the native Things window forward, retrying the action (not just polling a
# possibly failed activation). All retries belong to this one summon operation.
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
YABAI=/opt/homebrew/bin/yabai
JQ=/opt/homebrew/bin/jq
visibility="$HOME/.config/scripts/things/things_visibility"
wid="$1"
space="$2"
# Things can have several main windows. Its scripting window ID is the actual
# macOS window ID; never raise an arbitrary first entry from yabai's window list.
"$visibility" unhide >/dev/null 2>&1 || true
front_id=$(/usr/bin/osascript - "${3:-}" <<'APPLESCRIPT'
on run argv
    tell application "Things3"
        set targetName to ""
        if item 1 of argv starts with "tag:" then
            set targetName to name of tag id (text 5 thru -1 of (item 1 of argv))
        else if item 1 of argv is not "" then
            set targetName to name of project id (item 1 of argv)
        end if
        repeat 50 times
            try
                if (count of windows) > 0 then
                    if targetName is "" or name of front window is targetName then return id of front window
                end if
            end try
            delay 0.02
        end repeat
        error "Things 尚未打开目标窗口，请重试。"
    end tell
end run
APPLESCRIPT
) || exit 1
if [[ "$front_id" =~ ^[0-9]+$ ]]; then wid="$front_id"; fi
for ((attempt=0; attempt<20; attempt++)); do
    "$visibility" unhide >/dev/null 2>&1 || true
    window=$("$YABAI" -m query --windows --window "$wid" 2>/dev/null)
    if ! printf '%s' "$window" | "$JQ" -e '.app == "Things" and .subrole == "AXStandardWindow"' >/dev/null 2>&1; then
        wid=$("$YABAI" -m query --windows | "$JQ" -er '[.[] | select(.app == "Things" and .subrole == "AXStandardWindow")] | sort_by(."has-focus", ."is-visible") | reverse | .[0].id') || exit 1
        window=$("$YABAI" -m query --windows --window "$wid")
    fi
    if [ "$(printf '%s' "$window" | "$JQ" -r '."is-minimized"')" = true ]; then
        "$YABAI" -m window --deminimize "$wid" 2>/dev/null || true
    fi
    if [ "$(printf '%s' "$window" | "$JQ" -r '.space')" != "$space" ]; then
        "$YABAI" -m window "$wid" --space "$space" 2>/dev/null || true
    fi
    "$visibility" show >/dev/null 2>&1 || true
    "$YABAI" -m window --focus "$wid" 2>/dev/null || true
    if "$YABAI" -m query --windows --window | "$JQ" -e --argjson wid "$wid" --argjson space "$space" '.id == $wid and .space == $space and ."has-focus" and ."is-visible" and (."is-hidden" | not) and (."is-minimized" | not)' >/dev/null; then
        # Things keeps hidden sidebar AX nodes and can expose stale menu titles.
        # Detect visibility from the main content's left edge in the focused window.
        /usr/bin/osascript <<'APPLESCRIPT' || exit 1
on sidebarVisible(w)
    tell application "System Events"
        if (count of scroll areas of w) < 2 then return false
        set contentPosition to get position of scroll area 1 of w
        set windowPosition to get position of w
        set sidebarSize to get size of scroll area 2 of w
        set contentLeft to item 1 of contentPosition
        set windowLeft to item 1 of windowPosition
        set sidebarWidth to item 1 of sidebarSize
        return sidebarWidth > 80 and contentLeft - windowLeft > sidebarWidth - 10
    end tell
end sidebarVisible

tell application "System Events" to tell process "Things3"
    if not frontmost then return
    set w to value of attribute "AXFocusedWindow"
    if value of attribute "AXSubrole" of w is not "AXStandardWindow" then return
    if my sidebarVisible(w) then
        -- Native command, with no menu flash and no repeat toggle.
        key code 44 using command down
        repeat 15 times
            delay 0.02
            if not frontmost then return
            if not my sidebarVisible(w) then return
        end repeat
        error "Things sidebar did not close"
    end if
end tell
APPLESCRIPT
        exit 0
    fi
    sleep 0.05
done
exit 1
