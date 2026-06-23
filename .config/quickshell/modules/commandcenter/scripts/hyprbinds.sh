#!/usr/bin/env bash
# Emit hyprland keybinds as JSON lines for Quickshell Command Center.
set -euo pipefail

command -v hyprctl >/dev/null || exit 0
command -v jq >/dev/null || exit 0

hyprctl -j binds 2>/dev/null | jq -rc '
  .[] | select(.key != null and .key != "") |
  ((.modmask // 0) | tonumber) as $m |
  [
    (if ($m % 128) >= 64 then "SUPER" else empty end),
    (if ($m % 16)  >= 8 then "ALT" else empty end),
    (if ($m % 8)   >= 4 then "CTRL" else empty end),
    (if ($m % 2)   >= 1 then "SHIFT" else empty end)
  ] as $mods |
  {
    combo: (if ($mods | length) > 0 then ($mods | join("+")) + "+" + (.key | ascii_upcase) else (.key | ascii_upcase) end),
    description: (.description // ""),
    dispatcher: (.dispatcher // ""),
    arg: (.arg // "")
  } | select(.dispatcher != "")
'
