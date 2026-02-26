#!/usr/bin/env bash
# ==============================================================================
# WLSUNSET TEMPERATURE CONTROLLER
# Usage: wltemp.sh {up|down|set <kelvin>|show}
# Stores current target in ~/.cache/wltemp
# Range: 1000K (candlelight) → 6500K (daylight)
# ==============================================================================

set -euo pipefail

readonly TEMP_CACHE="$HOME/.cache/wltemp"
readonly TEMP_MAX=6500
readonly TEMP_MIN=1000
readonly STEP=250           # Kelvin per press
readonly NOTIF_ID=558

_read_temp() {
  if [[ -f "$TEMP_CACHE" ]]; then
    cat "$TEMP_CACHE"
  else
    echo "4000"
  fi
}

_write_temp() {
  echo "$1" > "$TEMP_CACHE"
}

_clamp() {
  local val=$1
  (( val < TEMP_MIN )) && val=$TEMP_MIN
  (( val > TEMP_MAX )) && val=$TEMP_MAX
  echo "$val"
}

_temp_label() {
  local temp=$1
  if   (( temp >= 6000 )); then echo "Daylight"
  elif (( temp >= 5000 )); then echo "Cool White"
  elif (( temp >= 4000 )); then echo "Neutral"
  elif (( temp >= 3000 )); then echo "Warm"
  elif (( temp >= 2000 )); then echo "Amber"
  else                          echo "Candlelight"
  fi
}

_apply() {
  local temp=$1
  if pgrep -x "wlsunset" >/dev/null; then
    pkill wlsunset
    sleep 0.05
    wlsunset -t "$temp" -T "$TEMP_MAX" &
  fi
  _write_temp "$temp"
  notify-send -r $NOTIF_ID -a "Display" "Color Temperature" \
    "󱩘  ${temp}K — $(_temp_label "$temp")" -t 1800
}

current=$(_read_temp)

case "${1:-show}" in
  up)
    new=$(( current + STEP ))
    _apply "$(_clamp "$new")"
    ;;
  down)
    new=$(( current - STEP ))
    _apply "$(_clamp "$new")"
    ;;
  set)
    target="${2:?Usage: wltemp.sh set <kelvin>}"
    _apply "$(_clamp "$target")"
    ;;
  show)
    notify-send -r $NOTIF_ID -a "Display" "Color Temperature" \
      "󱩘  ${current}K — $(_temp_label "$current")" -t 1800
    ;;
  *)
    echo "Usage: $0 {up|down|set <kelvin>|show}"
    exit 1
    ;;
esac
