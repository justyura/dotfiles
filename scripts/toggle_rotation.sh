#!/bin/bash
# Toggle main display rotation between 0° and 90°

current=$(/opt/homebrew/bin/displayplacer list | grep "Rotation:" | head -1 | awk '{print $2}')

if [ "$current" = "90" ]; then
  /opt/homebrew/bin/displayplacer "id:54525BFA-482A-40BB-9C10-8EE4391233A3 degree:0"
else
  /opt/homebrew/bin/displayplacer "id:54525BFA-482A-40BB-9C10-8EE4391233A3 degree:90"
fi
