#!/usr/bin/env bash
# ==============================================================================
# CLOUDYY KEYBIND VIEWER
# Uses hyprctl -j binds (live data, picks up bindd descriptions automatically)
# Place at: ~/cloudyy_scripts/keybinds.sh
# Deps: hyprctl, jq, rofi
# ==============================================================================

set -uo pipefail

readonly DELIM=$'\x1f'

declare -a ROFI_ARGS=(
  rofi -dmenu -i
  -markup-rows
  -p "Keybinds"
  -mesg "Type to filter  •  Enter to run bind"
  -theme-str 'window { width: 45%; }'
  -theme-str 'listview { fixed-height: true; lines: 15; }'
  -theme-str 'element { padding: 7px 14px; }'
  -theme-str 'element-text { font: "JetBrainsMono Nerd Font 12"; }'
)

# ── dep check ─────────────────────────────────────────────────────────────────

for cmd in hyprctl jq rofi; do
  command -v "$cmd" >/dev/null 2>&1 || {
    notify-send -u critical "Keybinds" "Missing dependency: $cmd"
    exit 1
  }
done

# ── build display list ────────────────────────────────────────────────────────

DATA=$(hyprctl -j binds 2>/dev/null | jq -r --arg d "$DELIM" '
  .[] | select(.key != null and .key != "") |
  ((.modmask // 0) | tonumber) as $m |
  [
    (if ($m % 2)   >= 1 then "SHIFT" else empty end),
    (if ($m % 8)   >= 4 then "CTRL"  else empty end),
    (if ($m % 16)  >= 8 then "ALT"   else empty end),
    (if ($m % 128) >= 64 then "SUPER" else empty end)
  ] as $mods |
  [
    ($mods | join("+")),
    .key,
    (.description // ""),
    (.dispatcher  // ""),
    (.arg         // ""),
    (.submap      // "")
  ] | join($d)
' | awk -F"$DELIM" -v delim="$DELIM" '
{
  mods=$1; key=$2; desc=$3; disp=$4; arg=$5; submap=$6
  if (disp == "") next

  key = toupper(key)

  # ── icon per dispatcher ──
  icon = " "
  if (disp ~ /exec/)         icon = " "
  else if (disp ~ /kill/)    icon = " "
  else if (disp ~ /exit/)    icon = "󰩈 "
  else if (disp ~ /resize/)  icon = "󰩨 "
  else if (disp ~ /movewin/) icon = "󰆾 "
  else if (disp ~ /float/)   icon = " "
  else if (disp ~ /fullsc/)  icon = " "
  else if (disp ~ /work/)    icon = " "
  else if (disp ~ /focus/)   icon = "󰁕 "
  else if (disp ~ /toggle/)  icon = " "
  else if (disp ~ /pin/)     icon = "󰐃 "
  else if (disp ~ /pass/)    icon = " "

  # ── escape HTML for pango ──
  gsub(/&/, "\\&amp;",  desc); gsub(/</, "\\&lt;",  desc); gsub(/>/, "\\&gt;",  desc)
  gsub(/&/, "\\&amp;",  arg);  gsub(/</, "\\&lt;",  arg);  gsub(/>/, "\\&gt;",  arg)
  gsub(/&/, "\\&amp;",  disp); gsub(/</, "\\&lt;",  disp); gsub(/>/, "\\&gt;",  disp)

  # ── combo column ──
  if (mods != "")
    combo = sprintf("<span alpha=\"60%%\">%-14s</span>  <span weight=\"bold\">%-10s</span>", mods, key)
  else
    combo = sprintf("<span alpha=\"60%%\">%-14s</span>  <span weight=\"bold\">%-10s</span>", "", key)

  # ── label column ──
  if (desc != "")
    label = desc
  else if (arg != "")
    label = disp "  <span alpha=\"55%\" style=\"italic\">" arg "</span>"
  else
    label = disp

  # ── submap badge ──
  if (submap != "" && submap != "global")
    label = "<span weight=\"bold\" foreground=\"#f38ba8\">[" toupper(submap) "]</span>  " label

  # display row delim disp delim arg
  printf "%s  %s    %s%s%s%s%s\n", icon, combo, label, delim, disp, delim, arg
}
' | sort -t"$DELIM" -k1,1 -u)

[[ -z "${DATA:-}" ]] && {
  notify-send "Keybinds" "No bindings returned by hyprctl"
  exit 0
}

# ── show rofi ─────────────────────────────────────────────────────────────────

SELECTED_INDEX=$(awk -F"$DELIM" '{print $1}' <<<"$DATA" |
  "${ROFI_ARGS[@]}" -format i) || exit 0

if [[ "$SELECTED_INDEX" =~ ^[0-9]+$ ]]; then
  LINE=$(sed -n "$((SELECTED_INDEX + 1))p" <<<"$DATA")
  IFS="$DELIM" read -r _ disp arg <<<"$LINE"
  [[ -n "$disp" ]] && hyprctl dispatch "$disp" "${arg:-}"
fi
