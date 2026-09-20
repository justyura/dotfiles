# Bootstrap and platform layout

The repository contains three explicit layers:

- `profiles/common`: configuration used on both macOS and Linux.
- `profiles/macos`: macOS applications and automation.
- `profiles/linux`: the portable script subset used on Linux.

The profile files are intentionally plain lists. Add one relative path per line. The installer
links each listed path from the checkout into the same location below `~/.config`.

## New machine

From a checked-out repository:

```sh
./bootstrap.sh
```

Without a checkout:

```sh
curl -fsSL https://raw.githubusercontent.com/justyura/dotfiles/main/bootstrap.sh | sh
```

The remote form clones to `~/.local/share/dotfiles`. Override that with `DOTFILES_DIR`, and
override the clone URL with `DOTFILES_REPO`. Existing target files are never deleted: they are
moved below `~/.local/state/dotfiles/backups/<timestamp>` before links are created.

Useful modes:

```sh
./bootstrap.sh --dry-run
./bootstrap.sh --config-only
./bootstrap.sh --repo-dir "$HOME/src/dotfiles"
```

Run `--dry-run` from an existing checkout so the script can inspect its profile files without
first cloning them.

By default macOS packages come from `packages/Brewfile`. Linux supports apt, pacman, and dnf;
the corresponding package names live together in `install_packages()` in `bootstrap.sh` so the
mapping is easy to audit. The portable dependencies are Git, curl, Neovim, tmux, fzf, ripgrep,
jq, and xclip.

The Neovim configuration requires Neovim 0.12 or newer. Some stable Linux distributions ship
an older build, so Linux bootstrap checks the active binary and, when necessary, installs the
official release archive below `/opt/dotfiles/` with an entry point at `/usr/local/bin/nvim`.
Existing unmanaged files at that entry point are never overwritten.

The `nvim-treesitter` main branch also requires tree-sitter CLI 0.26.1 or newer and a C compiler.
Bootstrap installs the compiler toolchain from the Linux package manager and the official CLI
release below `/opt/dotfiles/`, exposed as `/usr/local/bin/tree-sitter`. macOS installs the CLI
through Homebrew.

The normal install also bootstraps TPM under `~/.tmux/plugins/tpm` and installs the plugins from
`tmux.conf`. Neovim bootstraps lazy.nvim and its plugins on first launch.

Homebrew itself is not installed automatically. This avoids executing a second remote installer
inside the bootstrap. If Homebrew is absent, install it from <https://brew.sh> and rerun, or use
`--config-only`.

## Machine-local settings

Secrets, SSH configuration, GitHub credentials, and app-generated state do not belong in this
repository. For one-machine-only setup, create an untracked `bootstrap.local.sh`; it runs after
the profiles are linked and receives `DOTFILES_PLATFORM` and `DOTFILES_DIR`.

Use `bootstrap.local.sh.example` as a starting point. Keep it idempotent: check current state
before changing it, and make repeated runs harmless.

Machine identifiers and application mappings stay untracked. For example,
`scripts/toggle_rotation.sh` reads the displayplacer ID from `DISPLAYPLACER_ID` or
`~/.config/local/display_id`, while the Infinite Canvas integration creates its Things project
mapping locally under `~/.config/things/`.

## Updating

Run `bootstrap.sh` again. A remote checkout is fast-forwarded, package installation is
idempotent, correct links are retained, and newly added profile entries are deployed. The script
will stop rather than merge a diverged Git checkout.

## Recovering an existing configuration

When bootstrap encounters an existing target, it prints the exact backup directory and moves
the old target there before linking the repository version. To restore one entry, unlink its
deployed symlink and move the corresponding entry from that backup directory back into
`~/.config`. Inspect both paths before doing so; the installer never deletes backups.

macOS still needs the permissions required by yabai, skhd, Karabiner-Elements, and SketchyBar.
Those permissions are intentionally not automated because macOS requires user confirmation.
