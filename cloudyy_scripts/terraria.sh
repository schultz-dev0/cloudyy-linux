#!/bin/bash
# Steam launch option: ~/cloudyy_scripts/terraria.sh %command%
# Ignores the container-wrapped "$@" so the game runs on host libs (needed for native Wayland SDL3).
cd ~/.local/share/Steam/steamapps/common/Terraria || exit 1
export SteamAppId=105600 SDL_VIDEODRIVER=wayland
exec ./Terraria
