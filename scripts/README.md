# Personal scripts

Personal automation lives here. App configuration stays in `skhd/`, `yabai/`,
`sketchybar/`, `tmux/`, and `nvim/`; third-party plugin code stays with its plugin.

| Directory | Purpose |
| --- | --- |
| `things/` | Native Things popup, project routing, bar task list, task capture, Swift helpers |
| `sketchybar/` | Bar events, agents, activity history, breaks and progress |
| `sketchybar/helpers/` | Bar Swift sources, executables and presence app |
| `yabai/` | Workspace history, HUD, bar padding and window helpers |
| `tmux/` | Session selection and pane export |
| `tmux/status/` | Status-line scripts |
| `apps/` | Other application toggles |
| `cold_turkey/` | Cold Turkey helper |
| This directory | Shared search, lookup, keyboard and window utilities |

## Entry points

- `things/toggle_things.sh`: tap right Option (Karabiner sends F16 to skhd).
  InfiniteCanvas uses its current-project JSON and a persistent Things project ID mapping;
  Safari opens the Safari project; other applications use the most recently active tmux session.
- Control + right Option: `things/infinitecanvas_context.py quick-add` opens Quick Entry for the current Canvas project.
- `things/things_open.sh <id>`: show a task from the bar in the native popup.
- `things/things_capture.sh --edit`: tmux task capture.
- `yabai/workspace_history.sh`: workspace navigation and history.
- `yabai/toggle_top_padding.sh`: show/hide the bar and coordinate padding.

Keep helper sources beside their executables. `things/toggle_things.sh` rebuilds
its visibility helper automatically when the source changes or the binary is absent.

Old script locations are compatibility symlinks, not additional copies. They keep
already-running callbacks, cached commands and external callers working. Edit the
files here and use these paths for new references. Do not replace a compatibility
link with a second implementation.

`skhd/things_jump` and `skhd/things_passthrough` remain in `skhd/`: they are keybinding
configuration, not executable scripts. `sketchybar/settings.sh` is likewise bar
configuration. Project-local build scripts remain with their projects.
