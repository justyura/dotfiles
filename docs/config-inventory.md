# Configuration inventory

This is the boundary used by the bootstrap. It is deliberately smaller than everything an app
may have written below `~/.config`.

| Layer | Paths | Notes |
| --- | --- | --- |
| Common | `nvim`, `tmux` | Editor and terminal workflow on macOS and Linux |
| Linux | `scripts/tmux` | Portable tmux helpers only |
| macOS | `karabiner`, `scripts`, `sketchybar`, `skhd`, `yabai` | Keyboard and window-management stack |
| Machine-local | `bootstrap.local.sh` | Untracked hook for private paths and per-host setup |

## Intentionally not synchronized

The `.gitignore` list is the source of truth. It excludes application-generated state and
credentials such as `gh/hosts.yml`. SSH keys, tokens, caches, runtime databases, and application
permissions must stay outside the repository.

Only committed files exist on a new machine. Before relying on bootstrap changes, review
`git status --short` and commit the configuration and scripts that should travel. Backup files
with names such as `*.before-*` should normally remain local or be removed instead of committed.

## Known platform boundaries

- `yabai`, `skhd`, SketchyBar, Karabiner, AppleScript, Swift helpers, and Things integration are
  macOS-only and are not linked by the Linux profile.
- `tmux.conf` guards its SketchyBar and Things hooks with a Darwin check.
- `nvim` is shared. Clipboard integration therefore needs `xclip` on the supported Linux setup.
- Personal absolute paths that remain inside macOS automation belong in `bootstrap.local.sh` or
  should gradually become environment variables; they do not affect the Linux profile.
