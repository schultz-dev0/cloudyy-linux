#!/usr/bin/env bash
# volume-slider.sh — volume control via swayosd
#
# Binds:
#   bindel = $mainMod, up,   exec, $scripts/volume-slider.sh up
#   bindel = $mainMod, down, exec, $scripts/volume-slider.sh down
#   bindl  = $mainMod, m,    exec, $scripts/volume-slider.sh mute
#
# Deps: swayosd-server (exec-once in hyprland.conf), swayosd-client

STEP=5

case "${1:-}" in
    up)   swayosd-client --output-volume "+${STEP}" ;;
    down) swayosd-client --output-volume "-${STEP}" ;;
    mute) swayosd-client --output-volume mute-toggle ;;
    *)    echo "Usage: $(basename "$0") {up|down|mute}"; exit 1 ;;
esac