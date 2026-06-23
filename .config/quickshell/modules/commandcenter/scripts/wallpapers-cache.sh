#!/usr/bin/env bash
# Instant wallpaper catalog read for Quickshell
set -euo pipefail

home="${HOME:-$(printf '%s' ~)}"
state="${home}/.config/hypr/theme_state/state.conf"
mode="dark"

if [[ -f "$state" ]]; then
  raw_mode=$(grep -m1 '^THEME_MODE=' "$state" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'[:space:]')
  [[ "$raw_mode" == "light" ]] && mode="light"
fi

cache="${home}/.cache/rofi_thumbs/picker_catalog_${mode}.json"
[[ -f "$cache" ]] || exit 0
cat "$cache"
