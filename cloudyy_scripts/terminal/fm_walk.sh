#!/usr/bin/env bash
# Open Nautilus in the cwd of the focused terminal window.
# Bind to a Hyprland key for the reverse of cwd_walk.sh.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=terminal/cwd_walk_lib.sh
source "${SCRIPT_DIR}/cwd_walk_lib.sh"

notify() {
  command -v notify-send &>/dev/null || return 0
  notify-send "Files" "$1"
}

main() {
  command -v hyprctl &>/dev/null || { notify "hyprctl not found"; exit 1; }
  command -v jq &>/dev/null || { notify "jq not found"; exit 1; }
  command -v nautilus &>/dev/null || { notify "nautilus not found"; exit 1; }

  local cwd
  if ! cwd=$(cwd_walk_resolve_focused); then
    cwd="$HOME"
  fi

  # --new-window ensures Nautilus opens in the given dir even when already running as a daemon.
  if command -v uwsm-app &>/dev/null; then
    exec uwsm-app -- nautilus --new-window "$cwd"
  fi

  exec nautilus --new-window "$cwd"
}

main "$@"
