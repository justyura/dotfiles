#!/bin/sh

# Install this dotfiles repository on macOS or Linux.
#
# Local use:
#   ./bootstrap.sh
# Remote use:
#   curl -fsSL https://raw.githubusercontent.com/justyura/dotfiles/main/bootstrap.sh | sh
#
# The script is deliberately POSIX sh: a fresh machine only needs curl and git.

set -eu

REPO_URL=${DOTFILES_REPO:-https://github.com/justyura/dotfiles.git}
REPO_DIR=${DOTFILES_DIR:-"${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles"}
CONFIG_DIR=${XDG_CONFIG_HOME:-"$HOME/.config"}
STATE_DIR=${XDG_STATE_HOME:-"$HOME/.local/state"}/dotfiles
INSTALL_PACKAGES=1
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bootstrap.sh [options]

Options:
  --config-only       Link configuration but do not install packages
  --dry-run           Print changes without making them
  --repo URL          Clone URL (or set DOTFILES_REPO)
  --repo-dir PATH     Checkout directory (or set DOTFILES_DIR)
  -h, --help          Show this help

Existing configuration is moved to a timestamped directory under
~/.local/state/dotfiles/backups before a link is created.
EOF
}

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+ '
    printf "'%s' " "$@"
    printf '\n'
  else
    "$@"
  fi
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    run "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required to install Linux packages"
    run sudo "$@"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --config-only) INSTALL_PACKAGES=0 ;;
    --dry-run) DRY_RUN=1 ;;
    --repo)
      [ "$#" -ge 2 ] || die "--repo needs a value"
      REPO_URL=$2
      shift
      ;;
    --repo-dir)
      [ "$#" -ge 2 ] || die "--repo-dir needs a value"
      REPO_DIR=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux) PLATFORM=linux ;;
  *) die "supported platforms are macOS and Linux" ;;
esac

# When run from a checkout, use that checkout. When piped from curl, clone one.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd || true)
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bootstrap.sh" ] && [ -f "$SCRIPT_DIR/profiles/common" ]; then
  REPO_DIR=$SCRIPT_DIR
elif [ -d "$REPO_DIR/.git" ]; then
  say "Updating $REPO_DIR"
  if [ "$DRY_RUN" -eq 0 ]; then
    git -C "$REPO_DIR" pull --ff-only
  fi
else
  command -v git >/dev/null 2>&1 || die "git is required to download the configuration"
  say "Cloning $REPO_URL into $REPO_DIR"
  run mkdir -p "$(dirname "$REPO_DIR")"
  run git clone "$REPO_URL" "$REPO_DIR"
fi

[ -f "$REPO_DIR/profiles/common" ] || die "profile files are missing from $REPO_DIR"

install_packages() {
  [ "$INSTALL_PACKAGES" -eq 1 ] || return 0

  say "Installing $PLATFORM packages"
  case "$PLATFORM" in
    macos)
      if ! command -v brew >/dev/null 2>&1; then
        die "Homebrew is not installed. Install it from https://brew.sh, then rerun this script (or use --config-only)."
      fi
      run brew bundle --file "$REPO_DIR/packages/Brewfile"
      ;;
    linux)
      # Package names are kept here because they differ by distribution.
      if command -v apt-get >/dev/null 2>&1; then
        as_root apt-get update
        as_root apt-get install -y git curl neovim tmux fzf ripgrep jq xclip
      elif command -v pacman >/dev/null 2>&1; then
        as_root pacman -S --needed git curl neovim tmux fzf ripgrep jq xclip
      elif command -v dnf >/dev/null 2>&1; then
        as_root dnf install -y git curl neovim tmux fzf ripgrep jq xclip
      else
        die "unsupported Linux package manager; rerun with --config-only and install packages listed in docs/bootstrap.md"
      fi
      ;;
  esac
}

same_path() {
  [ -e "$1" ] || [ -L "$1" ] || return 1
  [ -e "$2" ] || [ -L "$2" ] || return 1
  [ "$(CDPATH= cd -- "$(dirname "$1")" && pwd -P)/$(basename "$1")" = \
    "$(CDPATH= cd -- "$(dirname "$2")" && pwd -P)/$(basename "$2")" ] && return 0
  [ "$(readlink "$2" 2>/dev/null || true)" = "$1" ]
}

BACKUP_DIR=$STATE_DIR/backups/$(date '+%Y%m%d-%H%M%S')-$$

deploy_entry() {
  entry=$1
  case "$entry" in
    /*|../*|*/../*|*/..) die "profile path must stay below ~/.config: $entry" ;;
  esac
  source_path=$REPO_DIR/$entry
  target_path=$CONFIG_DIR/$entry

  if [ ! -e "$source_path" ] && [ ! -L "$source_path" ]; then
    say "Skipping missing optional path: $entry"
    return
  fi
  if same_path "$source_path" "$target_path"; then
    say "Already active: $entry"
    return
  fi

  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    backup_path=$BACKUP_DIR/$entry
    say "Backing up $target_path to $backup_path"
    run mkdir -p "$(dirname "$backup_path")"
    run mv "$target_path" "$backup_path"
  fi

  say "Linking $target_path -> $source_path"
  run mkdir -p "$(dirname "$target_path")"
  run ln -s "$source_path" "$target_path"
}

deploy_profile() {
  profile=$1
  while IFS= read -r entry || [ -n "$entry" ]; do
    case "$entry" in ''|'#'*) continue ;; esac
    deploy_entry "$entry"
  done < "$REPO_DIR/profiles/$profile"
}

install_packages
run mkdir -p "$CONFIG_DIR"
deploy_profile common
deploy_profile "$PLATFORM"

install_tmux_plugins() {
  [ "$INSTALL_PACKAGES" -eq 1 ] || return 0
  # Keep this in sync with the final `run` line in tmux/tmux.conf.
  tpm_dir=$HOME/.tmux/plugins/tpm
  if [ ! -d "$tpm_dir/.git" ]; then
    say "Installing tmux plugin manager"
    run mkdir -p "$(dirname "$tpm_dir")"
    run git clone --depth 1 https://github.com/tmux-plugins/tpm "$tpm_dir"
  fi
  if [ -x "$tpm_dir/bin/install_plugins" ]; then
    run "$tpm_dir/bin/install_plugins"
  fi
}

install_tmux_plugins

if command -v nvim >/dev/null 2>&1; then
  nvim_minor=$(nvim --version | sed -n '1s/.* v0\.\([0-9][0-9]*\).*/\1/p')
  if [ -n "$nvim_minor" ] && [ "$nvim_minor" -lt 11 ]; then
    warn "this Neovim configuration needs 0.11 or newer; install a newer build than the distribution package"
  fi
fi

# Optional, untracked machine-specific finishing steps.
if [ -f "$REPO_DIR/bootstrap.local.sh" ]; then
  say "Running bootstrap.local.sh"
  if [ "$DRY_RUN" -eq 0 ]; then
    DOTFILES_PLATFORM=$PLATFORM DOTFILES_DIR=$REPO_DIR sh "$REPO_DIR/bootstrap.local.sh"
  fi
fi

say "Done. Active profile: common + $PLATFORM"
if [ -d "$BACKUP_DIR" ]; then
  say "Previous files were saved in $BACKUP_DIR"
fi
