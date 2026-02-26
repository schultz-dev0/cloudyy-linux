#!/usr/bin/env bash
# ==============================================================================
# VOLUME SCRIPT — swayosd
# Usage: volume.sh {up|down|mute}
# ==============================================================================

set -euo pipefail

readonly STEP=5
readonly NOTIF_ID=556

_ensure_server() {
  if ! pgrep -x "swayosd-server" >/dev/null; then
    swayosd-server &
    sleep 0.1
  fi
}

_current_volume() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%d", $2 * 100}'
}

_is_muted() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q "\[MUTED\]"
}

_ensure_server

case "${1:-show}" in
  up)
    swayosd-client --output-volume "+${STEP}"
    notify-send -r $NOTIF_ID -a "Audio" "Volume" "󰕾  $(_current_volume)%" -t 1500
    ;;
  down)
    swayosd-client --output-volume "-${STEP}"
    notify-send -r $NOTIF_ID -a "Audio" "Volume" "󰕿  $(_current_volume)%" -t 1500
    ;;
  mute)
    swayosd-client --output-volume mute-toggle
    if _is_muted; then
      notify-send -r $NOTIF_ID -a "Audio" "Volume" "󰖁  Muted" -t 1500
    else
      notify-send -r $NOTIF_ID -a "Audio" "Volume" "󰕾  $(_current_volume)%" -t 1500
    fi
    ;;
  set)
    swayosd-client --output-volume "${2:-50}"
    ;;
  *)
    echo "Usage: $0 {up|down|mute|set <val>}"
    exit 1
    ;;
esac
