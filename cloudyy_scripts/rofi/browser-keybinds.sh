#!/usr/bin/env bash
# ==============================================================================
# CLOUDYY ZEN BROWSER KEYBIND VIEWER (REFINED)
# Extracts ALL 120+ keybinds from zen-keyboard-shortcuts.json
# ==============================================================================

set -uo pipefail

# Auto-detect Zen profile directory by scanning profiles.ini for the profile
# that contains zen-keyboard-shortcuts.json
_detect_zen_profile() {
  local ini="${HOME}/.config/zen/profiles.ini"
  [[ -f "$ini" ]] || return 1
  local path
  while IFS= read -r line; do
    if [[ "$line" =~ ^Path=(.+)$ ]]; then
      path="${BASH_REMATCH[1]}"
      [[ "$path" != /* ]] && path="${HOME}/.config/zen/${path}"
      [[ -f "${path}/zen-keyboard-shortcuts.json" ]] && { echo "$path"; return 0; }
    fi
  done < "$ini"
  return 1
}

PROFILE_DIR="$(_detect_zen_profile)" || {
  notify-send -u critical "Zen Binds" "Zen profile not found" 2>/dev/null
  exit 1
}
readonly PROFILE_DIR
readonly JSON_FILE="${PROFILE_DIR}/zen-keyboard-shortcuts.json"
readonly DELIM=$'\x1f'

declare -a ROFI_ARGS=(
  rofi -dmenu -i
  -markup-rows
  -p "Zen Binds"
  -mesg "Zen Browser Keyboard Shortcuts (All)"
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
  [
    (if .modifiers.accel   then "CTRL"  else empty end),
    (if .modifiers.control then "CTRL"  else empty end),
    (if .modifiers.alt     then "ALT"   else empty end),
    (if .modifiers.shift   then "SHIFT" else empty end),
    (if .modifiers.meta    then "META"  else empty end)
  ] as $mods |
  [
    ($mods | join("+")),
    (if (.key != null and .key != "") then .key 
     elif (.keycode != null and .keycode != "") then (.keycode | sub("^VK_"; ""))
     else "---" end),
    (if .id != null then (.id | sub("^key_"; "") | gsub("(?<=[a-z])(?=[A-Z])"; " ") | gsub("-"; " ") | ascii_upcase)
     elif .action != null then (.action | sub("^cmd_"; "") | gsub("(?<=[a-z])(?=[A-Z])"; " ") | ascii_upcase)
     else "UNKNOWN ACTION" end),
    (.group // "other")
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
  else if (desc ~ /ZEN/)     icon = " "

  # ── combo column ──
  if (mods != "")
    combo = sprintf("<span alpha=\"60%%\">%-14s</span>  <span weight=\"bold\">%-10s</span>", mods, key)
  else
    combo = sprintf("<span alpha=\"60%%\">%-14s</span>  <span weight=\"bold\">%-10s</span>", "", key)

  # ── label column ──
  label = desc
  if (group != "" && group != "other")
    label = label "  <span alpha=\"55%\" style=\"italic\">(" group ")</span>"

  printf "%s  %s    %s\n", icon, combo, label
}
' | sort -u)

# ── show rofi ─────────────────────────────────────────────────────────────────

echo "$DATA" | "${ROFI_ARGS[@]}" >/dev/null; exit 0
