# dotfiles

Personal configuration for macOS and Linux. A fresh machine uses one bootstrap script; shared
and platform-specific paths are selected explicitly instead of relying on every tool being
present everywhere.

```sh
curl -fsSL https://raw.githubusercontent.com/justyura/dotfiles/main/bootstrap.sh | sh
```

The installer is safe to rerun. It clones the repository to `~/.local/share/dotfiles`, installs
the small package set for the detected operating system, backs up conflicting configuration,
and links the `common` plus `macos` or `linux` profile into `~/.config`.

Read [docs/bootstrap.md](docs/bootstrap.md) before changing the layout or adding a new machine.
The implementation is plain POSIX shell and the deployment profiles are plain text files.

