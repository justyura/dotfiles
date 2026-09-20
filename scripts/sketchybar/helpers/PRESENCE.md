# Automatic break reminder

Settings: `../settings.sh`. The existing standup item ticks every 5 seconds,
including when the bar is hidden. No extra background daemon is installed.

- Keyboard/mouse activity counts toward the 45-minute reminder.
- After 180 seconds idle, pause unless a recent camera observation found a person.
- Five minutes away resets the counter. Shorter absences only pause it.
- Lock/sleep pauses counting; a long sleep resets the counter.
- Single click toggles the heatmap/history panel; it never pauses the timer.
- Click again, use the close row, or move away from the panel to dismiss it.
- The panel's explicit **开始休息** button pauses counting for the configured
  break length (5 minutes). The bar shows **Ⅱ 休息** and the button changes to
  **结束休息 · 恢复计时**. Finishing early preserves accumulated work; a full break
  resets it. At the deadline automatic idle/camera detection takes over again.
  Camera and activity observation continue throughout; the timeline separately
  labels the user-declared period **主动休息**, not camera-confirmed absence.
- **Option+S** also starts this break (including in Things/Agent keyboard modes).
  Repeated presses do not end it or restart the five-minute deadline.
- `R` means idle but a person was detected, not verified sitting.
- Camera failure/busy/denied falls back to keyboard/mouse idle inference.

`STANDUP_CAMERA=0` disables future camera samples and ignores previous observations.
`STANDUP_CAMERA_INTERVAL=60` samples at most once a minute, only during idle.
Each sample processes up to three low-resolution frames with Apple Vision and
stops capture; the process has an eight-second deadline. The camera indicator may
light briefly. Only `{status, at}` is written to `~/.cache/sketchybar/presence.json`;
images never go to disk or the network. No identity recognition is performed.

Camera permission belongs to **Standup Presence** (`local.yura.standup-presence`).
Grant/revoke it in macOS Privacy & Security → Camera. To request permission:

```sh
open -g ~/.config/scripts/sketchybar/helpers/StandupPresence.app --args --authorize
```

Rebuild: `bash ~/.config/scripts/sketchybar/helpers/build_presence.sh`.
Rebuilding the ad-hoc signed app may require granting camera permission again.

Presence is a heuristic: somebody standing in view still counts as present;
occlusion or poor lighting can look like absence. This does not measure posture.

## Daily activity timeline

Click the work reminder, then choose **每日活动时间线 ↗**. The existing
focus heatmap is unchanged. A local HTML report shows each recorded day, with
hover timestamps and expandable segments. Reopen it to refresh (no server).

Observations are appended every timer tick to
`~/.local/share/sketchybar/activity/YYYY-MM-DD.jsonl`. Nothing before installation
is reconstructed. Input within 15 seconds is labelled active (not keystroke-level
tracking); recent camera presence is a separate state. Before the idle threshold,
uncertain activity is idle; only a fresh absent camera observation means inferred
away. Missing camera data and gaps over 30 seconds are unknown, not away. Lock is
explicit, sleep gaps are not claimed as exact sleep/departure events. The report
stores timestamps, idle duration, lock state and camera result only. Files stay
local until manually deleted; there is no automatic retention limit.
