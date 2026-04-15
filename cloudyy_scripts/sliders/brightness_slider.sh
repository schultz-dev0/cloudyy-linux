#!/usr/bin/env bash
# brightness.sh — brightness control via brightnessctl + swayosd OSD
#
# Binds:
#   bindel = , XF86MonBrightnessUp,   exec, $scripts/brightness.sh up
#   bindel = , XF86MonBrightnessDown, exec, $scripts/brightness.sh down
#
# Deps: brightnessctl, swayosd-server (exec-once in hyprland.conf), swayosd-client

STEP=5
MIN=1

_brightness() {
    brightnessctl -m | awk -F, '{gsub(/%/, "", $4); print $4}'
}

case "${1:-}" in
    up)
        brightnessctl set "${STEP}%+" -q
        swayosd-client --brightness raise &
        ;;
    down)
        (( $(_brightness) <= MIN )) && exit 0
        brightnessctl set "${STEP}%-" -q
        swayosd-client --brightness lower &
        ;;
    *)
        echo "Usage: $(basename "$0") {up|down}"
        exit 1
        ;;
esac