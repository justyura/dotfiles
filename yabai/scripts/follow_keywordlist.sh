# #!/bin/bash
# window_id=$(/opt/homebrew/bin/yabai -m query --windows | /opt/homebrew/bin/jq -r '[.[] | select(.title | contains("KeywordList"))][0].id')
#
# if [ -n "$window_id" ] && [ "$window_id" != "null" ]; then
#   window_space=$(/opt/homebrew/bin/yabai -m query --windows --window "$window_id" | /opt/homebrew/bin/jq -r '.space')
#   current_space=$(/opt/homebrew/bin/yabai -m query --spaces --space | /opt/homebrew/bin/jq -r '.index')
#
#   if [ "$window_space" != "$current_space" ]; then
#     /opt/homebrew/bin/yabai -m window "$window_id" --space mouse
#     /opt/homebrew/bin/yabai -m window "$window_id" --warp last
#   fi
# fi
#!/bin/bash

things_id=$(/opt/homebrew/bin/yabai -m query --windows | /opt/homebrew/bin/jq -r '[.[] | select(.app == "Things")][0].id')

if [ -n "$things_id" ] && [ "$things_id" != "null" ]; then
  things_space=$(/opt/homebrew/bin/yabai -m query --windows --window "$things_id" | /opt/homebrew/bin/jq -r '.space')
  current_space=$(/opt/homebrew/bin/yabai -m query --spaces --space | /opt/homebrew/bin/jq -r '.index')
  
  if [ "$things_space" != "$current_space" ]; then
    /opt/homebrew/bin/yabai -m window "$things_id" --space mouse
    /opt/homebrew/bin/yabai -m window "$things_id" --warp last
  fi
fi
