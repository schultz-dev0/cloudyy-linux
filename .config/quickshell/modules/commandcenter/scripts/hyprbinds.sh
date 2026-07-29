#!/usr/bin/env bash
# Emit hyprland keybinds as JSON lines for Quickshell Command Center.
set -euo pipefail

command -v hyprctl >/dev/null || exit 0
command -v jq >/dev/null || exit 0

if hyprctl -j binds 2>/dev/null | jq -rc '
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
' 2>/dev/null; then
  exit 0
fi

# Some Hyprland builds produce malformed JSON for `hyprctl binds -j` but keep
# the plain `hyprctl binds` format stable. Fall back to that representation.
hyprctl binds 2>/dev/null | awk '
  function emit() {
    if (key != "" && dispatcher != "")
      print modmask "\t" key "\t" description "\t" dispatcher "\t" arg
  }
  $1 ~ /^bind/ {
    emit()
    modmask = key = description = dispatcher = arg = ""
    next
  }
  $1 == "modmask:" { modmask = $2; next }
  $1 == "key:" { key = $2; next }
  $1 == "description:" { sub(/^[[:space:]]*description:[[:space:]]*/, ""); description = $0; next }
  $1 == "dispatcher:" { dispatcher = $2; next }
  $1 == "arg:" { sub(/^[[:space:]]*arg:[[:space:]]*/, ""); arg = $0; next }
  END { emit() }
' | while IFS=$'\t' read -r modmask key description dispatcher arg; do
  mods=()
  (( modmask & 64 )) && mods+=("SUPER")
  (( modmask & 8 )) && mods+=("ALT")
  (( modmask & 4 )) && mods+=("CTRL")
  (( modmask & 1 )) && mods+=("SHIFT")
  if (( ${#mods[@]} > 0 )); then
    combo="$(IFS=+; echo "${mods[*]}")+${key^^}"
  else
    combo="${key^^}"
  fi
  jq -cn \
    --arg combo "$combo" \
    --arg description "$description" \
    --arg dispatcher "$dispatcher" \
    --arg arg "$arg" \
    '{combo: $combo, description: $description, dispatcher: $dispatcher, arg: $arg}'
done
