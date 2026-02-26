#!/usr/bin/env bash
# ==============================================================================
# NIGHT LIGHT — wlsunset + yad --scale temperature picker
# Deps: wlsunset, yad
# ==============================================================================

readonly TEMP_CACHE="$HOME/.cache/wltemp"
readonly TEMP_MIN=1000
readonly TEMP_MAX=6500
readonly NOTIF_ID=555

_read_temp() {
  [[ -f "$TEMP_CACHE" ]] && cat "$TEMP_CACHE" || echo "4000"
}

_write_temp() { echo "$1" >"$TEMP_CACHE"; }

_apply_temp() {
  local temp="$1"
  pkill wlsunset 2>/dev/null
  sleep 0.05
  wlsunset -t "$temp" -T "$TEMP_MAX" &
  _write_temp "$temp"
}

# ── toggle ───────────────────────────────────────────────────────────────────

if pgrep -x "wlsunset" >/dev/null; then
  pkill wlsunset
  exit 0
fi

# ── not on: enable immediately then open picker ──────────────────────────────

current=$(_read_temp)
_apply_temp "$current"

# ── yad slider — auto-close on release ───────────────────────────────────────
# coproc pipes yad stdout to us. --print-partial streams values while dragging.
# read -t 0.35 times out when values stop (i.e. finger/mouse released).
# Loop exits → we kill yad and apply the last received value.

coproc YAD { yad \
  --scale \
  --title="Night Light" \
  --text="<span font_desc='Monocraft 10'>Night Light</span>\n" \
  --min-value=$TEMP_MIN \
  --max-value=$TEMP_MAX \
  --value="$current" \
  --step=100 \
  --print-partial \
  --no-escape \
  --center \
  --width=400 \
  --borders=16 \
  --no-buttons \
  2>/dev/null; }

last_temp="$current"
while IFS= read -r -t 0.35 line <&${YAD[0]}; do
  [[ -n "$line" ]] && last_temp="$line"
done

kill "$YAD_PID" 2>/dev/null
wait "$YAD_PID" 2>/dev/null

_apply_temp "$last_temp"
