#!/usr/bin/env bash
# ==============================================================================
# CLOUDYY ZEN BROWSER KEYBIND VIEWER
# Extracts keybinds from zen-keyboard-shortcuts.json
# ==============================================================================

set -uo pipefail

readonly PROFILE_DIR="/home/schultz/.config/mozilla/firefox/7i31mCQb.Profile 1"
readonly JSON_FILE="${PROFILE_DIR}/zen-keyboard-shortcuts.json"
readonly DELIM=$'\x1f'

declare -a ROFI_ARGS=(
  rofi -dmenu -i
  -markup-rows
  -p "Zen Binds"
  -mesg "Zen Browser Keyboard Shortcuts"
  -theme-str 'window { width: 45%; }'
  -theme-str 'listview { fixed-height: true; lines: 15; }'
  -theme-str 'element { padding: 7px 14px; }'
  -theme-str 'element-text { font: "JetBrainsMono Nerd Font 12"; }'
)

# ── dep check ─────────────────────────────────────────────────────────────────

if [[ ! -f "$JSON_FILE" ]]; then
  notify-send -u critical "Zen Binds" "Shortcut file not found"
  exit 1
fi

# ── build display list ────────────────────────────────────────────────────────

DATA=$(jq -r --arg d "$DELIM" '
  .shortcuts[] | 
  select(.disabled == false) |
  [
    (if .modifiers.accel   then "CTRL"  else empty end),
    (if .modifiers.control then "CTRL"  else empty end),
    (if .modifiers.alt     then "ALT"   else empty end),
    (if .modifiers.shift   then "SHIFT" else empty end),
    (if .modifiers.meta    then "META"  else empty end)
  ] as $mods |
  [
    ($mods | join("+")),
    (.key // .keycode // "unknown"),
    (.id | sub("^key_"; "") | gsub("(?<=[a-z])(?=[A-Z])"; " ") | ascii_upcase),
    .group
  ] | join($d)
' "$JSON_FILE" | awk -F"$DELIM" -v delim="$DELIM" '
{
  mods=$1; key=$2; desc=$3; group=$4
  
  key = toupper(key)
  
  # ── icon per group ──
  icon = "󰈈 "
  if (group ~ /window/)      icon = "󰖲 "
  else if (group ~ /tab/)    icon = "󰓩 "
  else if (group ~ /edit/)   icon = "󰏫 "
  else if (group ~ /navi/)   icon = "󰈹 "
  else if (group ~ /tool/)   icon = "󱁤 "

  # ── combo column ──
  if (mods != "")
    combo = sprintf("<span alpha=\"60%%\">%-14s</span>  <span weight=\"bold\">%-10s</span>", mods, key)
  else
    combo = sprintf("<span alpha=\"60%%\">%-14s</span>  <span weight=\"bold\">%-10s</span>", "", key)

  # ── label column ──
  label = desc
  if (group != "")
    label = label "  <span alpha=\"55%\" style=\"italic\">(" group ")</span>"

  printf "%s  %s    %s\n", icon, combo, label
}
' | sort -u)

# ── show rofi ─────────────────────────────────────────────────────────────────

echo "$DATA" | "${ROFI_ARGS[@]}" >/dev/null; exit 0
