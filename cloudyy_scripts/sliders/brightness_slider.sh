#!/usr/bin/env bash
# brightness.sh — brightness control via brightnessctl + Quickshell OSD
#
# Binds:
#   bindel = , XF86MonBrightnessUp,   exec, $scripts/brightness.sh up
#   bindel = , XF86MonBrightnessDown, exec, $scripts/brightness.sh down
#
# Deps: brightnessctl, optional quickshell IPC target "sliders"

STEP=5
MIN=1

_brightness() {
    brightnessctl -m | awk -F, '{gsub(/%/, "", $4); print $4}'
}

case "${1:-}" in
    up)
        brightnessctl set "${STEP}%+" -q
        command -v qs >/dev/null 2>&1 && qs ipc call sliders showBrightness >/dev/null 2>&1 || true
        ;;
    down)
        (( $(_brightness) <= MIN )) && exit 0
        brightnessctl set "${STEP}%-" -q
        command -v qs >/dev/null 2>&1 && qs ipc call sliders showBrightness >/dev/null 2>&1 || true
        ;;
    *)
        echo "Usage: $(basename "$0") {up|down}"
        exit 1
        ;;
esac
