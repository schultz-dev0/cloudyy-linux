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

ACTIVE_CLASS=$(hyprctl activewindow -j | jq -r '.class // empty')

[[ -z "$ACTIVE_CLASS" ]] && die "could not determine active window class"

is_terminal() {
  local class="$1"
  for t in "${TERMINALS[@]}"; do
    [[ "${class,,}" == "${t,,}" ]] && return 0
  done
  return 1
}

if is_terminal "$ACTIVE_CLASS"; then
  MODS="CTRL_SHIFT"
else
  MODS="CTRL"
fi

hyprctl dispatch sendshortcut "${MODS}, ${KEY^^}, class:${ACTIVE_CLASS}"
