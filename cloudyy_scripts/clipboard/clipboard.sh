#!/usr/bin/env bash

set -euo pipefail

TERMINALS=(kitty Alacritty alacritty foot ghostty wezterm)

die() {
  echo "error: $*" >&2
  exit 1
}

command -v jq &>/dev/null || die "jq is not installed"
command -v hyprctl &>/dev/null || die "hyprctl is not installed"

[[ $# -ne 1 ]] && die "usage: $(basename "$0") <copy|paste>"

ACTION="$1"

case "$ACTION" in
copy) KEY="c" ;;
paste) KEY="v" ;;
*) die "unknown action: $ACTION" ;;
esac

WINDOW_INFO=$(hyprctl activewindow -j)
ACTIVE_CLASS=$(echo "$WINDOW_INFO" | jq -r '.class // empty')
ACTIVE_ADDRESS=$(echo "$WINDOW_INFO" | jq -r '.address // empty')
IS_XWAYLAND=$(echo "$WINDOW_INFO" | jq -r '.xwayland // false')

[[ -z "$ACTIVE_CLASS" ]] && die "could not determine active window class"
[[ -z "$ACTIVE_ADDRESS" ]] && die "could not determine active window address"

is_terminal() {
  local class="$1"
  for t in "${TERMINALS[@]}"; do
    [[ "${class,,}" == "${t,,}" ]] && return 0
  done
  return 1
}

if is_terminal "$ACTIVE_CLASS"; then
  HYPR_MODS="CTRL_SHIFT"
  XDOTOOL_MODS="ctrl+shift"
else
  HYPR_MODS="CTRL"
  XDOTOOL_MODS="ctrl"
fi

# XWayland apps (e.g. Obsidian, Firefox without MOZ_ENABLE_WAYLAND) cannot receive
# synthetic input from Hyprland's sendshortcut — it uses Wayland protocols that don't
# cross the XWayland boundary. xdotool injects via X11 directly and works for these.
# Native Wayland apps use sendshortcut, which is reliable when dispatched by Hyprland.
if [[ "$IS_XWAYLAND" == "true" ]]; then
  command -v xdotool &>/dev/null || die "xdotool is not installed (required for XWayland windows like Obsidian/Firefox)"
  xdotool key "${XDOTOOL_MODS}+${KEY}"
else
  hyprctl dispatch sendshortcut "${HYPR_MODS}, ${KEY^^}, address:${ACTIVE_ADDRESS}"
fi
