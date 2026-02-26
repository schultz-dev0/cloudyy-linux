#!/usr/bin/env bash
# ==============================================================================
# BRIGHTNESS SCRIPT — brightnessctl + swayosd
# Usage: brightness.sh {up|down|set <val>}
# Requires: brightnessctl, swayosd (optional — falls back to notify-send)
# ==============================================================================

set -euo pipefail

readonly STEP=5          # percent per press
readonly NOTIF_ID=557
readonly MIN_BRIGHTNESS=1  # never go fully dark

_get_brightness() {
  brightnessctl -m | awk -F, '{gsub(/%/,"",$4); print $4}'
}

_ensure_server() {
  if ! pgrep -x "swayosd-server" >/dev/null; then
    swayosd-server &
    sleep 0.1
  fi
}

_ensure_server

case "${1:-show}" in
  up)
    swayosd-client --brightness raise
    notify-send -r $NOTIF_ID -a "Display" "Brightness" "󰃟  $(_get_brightness)%" -t 1500
    ;;
  down)
    # Clamp at MIN_BRIGHTNESS so screen never goes black
    current=$(_get_brightness)
    if [ "$current" -le "$MIN_BRIGHTNESS" ]; then
      notify-send -r $NOTIF_ID -a "Display" "Brightness" "󰃞  At minimum ($MIN_BRIGHTNESS%)" -t 1500
      exit 0
    fi
    swayosd-client --brightness lower
    notify-send -r $NOTIF_ID -a "Display" "Brightness" "󰃞  $(_get_brightness)%" -t 1500
    ;;
  set)
    val="${2:-50}"
    # Clamp
    val=$(( val < MIN_BRIGHTNESS ? MIN_BRIGHTNESS : val ))
    val=$(( val > 100 ? 100 : val ))
    brightnessctl set "${val}%"
    notify-send -r $NOTIF_ID -a "Display" "Brightness" "󰃟  ${val}%" -t 1500
    ;;
  show)
    notify-send -r $NOTIF_ID -a "Display" "Brightness" "󰃟  $(_get_brightness)%" -t 1500
    ;;
  *)
    echo "Usage: $0 {up|down|set <val>|show}"
    exit 1
    ;;
esac
