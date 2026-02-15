#!/bin/bash
DIR=$1
FOCUSED=$(/opt/homebrew/bin/yabai -m query --spaces | jq -r '[.[] | select(.["has-focus"] == true) | .index] | .[0]')
OCCUPIED=$(/opt/homebrew/bin/yabai -m query --windows | jq -r '[.[] | select(.["is-sticky"] == false)] | group_by(.space) | .[].[-1].space' | sort -n)
SPACES=($OCCUPIED)
LEN=${#SPACES[@]}
[ "$LEN" -le 1 ] && exit 0
IDX=-1
for i in "${!SPACES[@]}"; do
  [ "${SPACES[$i]}" = "$FOCUSED" ] && IDX=$i && break
done
if [ "$DIR" = "next" ]; then
  NEXT=$(( (IDX + 1) % LEN ))
else
  NEXT=$(( (IDX - 1 + LEN) % LEN ))
fi
/opt/homebrew/bin/yabai -m window --space "${SPACES[$NEXT]}" && /opt/homebrew/bin/yabai -m space --focus "${SPACES[$NEXT]}" 2>/dev/null
EOF
