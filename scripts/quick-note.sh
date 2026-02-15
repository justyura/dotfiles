#!/bin/bash

NOTES_DIR="/Users/yura/Library/Mobile Documents/27N4MQEA55~pro~writer/Documents/notes"
DATE=$(date +"%Y-%m-%d")
FILE="$NOTES_DIR/$DATE.md"

if [ ! -f "$FILE" ]; then
    echo "# $DATE" > "$FILE"
    echo "" >> "$FILE"
fi

/opt/homebrew/bin/alacritty \
    --title QuickNote \
    --option "window.dimensions={ columns = 100, lines = 32 }" \
    -e nvim -n \
    -c "normal G" \
    -c "nnoremap <silent> <Esc> :wq<CR>" \
    -c "startinsert!" \
    "$FILE"
