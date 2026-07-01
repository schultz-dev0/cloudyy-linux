#!/usr/bin/env bash
# automode_switch.sh — Called by theme-automode.service every 5 minutes.
# Reads cycle.conf and switches light/dark based on the hour.
set -uo pipefail

CYCLE_CONF="${HOME}/.config/hypr/theme_state/cycle.conf"
THEME_CTL="${HOME}/cloudyy_scripts/theme_controller.sh"

AUTOMODE_ENABLED="false"
AUTOMODE_LIGHT_HOUR="7"
AUTOMODE_DARK_HOUR="20"

[[ -f "$CYCLE_CONF" ]] && \
  while IFS='=' read -r k v || [[ -n "$k" ]]; do
    v="${v%\"}"; v="${v#\"}";
    case "$k" in
      AUTOMODE_ENABLED)    AUTOMODE_ENABLED="$v" ;;
      AUTOMODE_LIGHT_HOUR) AUTOMODE_LIGHT_HOUR="$v" ;;
      AUTOMODE_DARK_HOUR)  AUTOMODE_DARK_HOUR="$v" ;;
    esac
  done < "$CYCLE_CONF"

[[ "$AUTOMODE_ENABLED" != "true" ]] && exit 0

NOW=$(date +%-H)
CURRENT_MODE=$("$THEME_CTL" get-mode 2>/dev/null || echo "dark")

if (( NOW >= AUTOMODE_LIGHT_HOUR && NOW < AUTOMODE_DARK_HOUR )); then
  TARGET="light"
else
  TARGET="dark"
fi

[[ "$CURRENT_MODE" == "$TARGET" ]] && exit 0
"$THEME_CTL" set --mode "$TARGET"
