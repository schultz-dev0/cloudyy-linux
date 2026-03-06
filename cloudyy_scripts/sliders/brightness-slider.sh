#!/usr/bin/env bash
# brightness.sh — brightness control via swayosd
#
# Binds:
#   bindel = , XF86MonBrightnessUp,   exec, $scripts/brightness.sh up
#   bindel = , XF86MonBrightnessDown, exec, $scripts/brightness.sh down
#
# Deps: swayosd-server (exec-once in hyprland.conf), swayosd-client, brightnessctl

MIN_BRIGHTNESS=1

_get_brightness() {
    brightnessctl -m | awk -F, '{gsub(/%/, "", $4); print $4}'
}

case "${1:-}" in
    up)
        swayosd-client --brightness raise
        ;;
    down)
        current=$(_get_brightness)
        if (( current <= MIN_BRIGHTNESS )); then
            exit 0
        fi
        swayosd-client --brightness lower
        ;;
    *)
        echo "Usage: $(basename "$0") {up|down}"
        exit 1
        ;;
esac