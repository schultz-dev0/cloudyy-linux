#!/usr/bin/env bash
set -uo pipefail

TEMP_FILE="/tmp/screenshot-popup-$(date +%s%N).png"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

REGION=$(slurp -d 2>/dev/null) || exit 0

grim -g "$REGION" "$TEMP_FILE"
wl-copy --type image/png < "$TEMP_FILE"
LD_PRELOAD=/usr/lib/libgtk4-layer-shell.so python3 "$SCRIPT_DIR/popup.py" "$TEMP_FILE" &
