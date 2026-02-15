#!/bin/bash
# Called on session-created hook to ensure numbering stays contiguous

python3 "$HOME/.config/tmux/scripts/session_manager.py" ensure
