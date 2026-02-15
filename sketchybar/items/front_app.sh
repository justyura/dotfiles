#!/bin/bash

sketchybar --add item front_app left \
           --set front_app \
                 icon.drawing=off \
                 label.font="SF Pro:Semibold:14.0" \
                 label.color=0xffc0caf5 \
                 label.padding_left=10 \
                 label.padding_right=10 \
                 background.color=0xff292e42 \
                 background.corner_radius=5 \
                 background.height=24 \
                 script="$HOME/.config/sketchybar/plugins/front_app.sh" \
           --subscribe front_app front_app_switched
