#!/usr/bin/env bash
# Open a terminal in the cwd of the focused Thunar window or terminal.
# Bound to SUPER+Return by default. Toggle in Cloud Center, Terminal settings.

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SETTINGS_FILE="${HOME}/.config/cloud-center/settings/terminal/cwd_walk"
# shellcheck source=terminal/cwd_walk_lib.sh
source "${SCRIPT_DIR}/cwd_walk_lib.sh"

notify() {
  command -v notify-send &>/dev/null || return 0
  notify-send "Terminal" "$1"
}

_cwd_walk_enabled() {
  [[ -f "$SETTINGS_FILE" ]] || return 0
  case "$(tr '[:upper:]' '[:lower:]' < "$SETTINGS_FILE")" in
    true|yes|1|on) return 0 ;;
  esac
  return 1
}

launch_terminal_plain() {
  local term=${TERMINAL:-kitty}

  if command -v uwsm-app &>/dev/null; then
    exec uwsm-app -- "${term}"
  fi

  exec "${term}"
}

launch_terminal() {
  local cwd=$1
  local term=${TERMINAL:-kitty}
  local term_bin

  term_bin=$(command -v "$term" 2>/dev/null || true)
  [[ -n "$term_bin" ]] || term_bin="$term"

  # Shell wrapper: cd first, then exec the real terminal binary.
  if command -v uwsm-app &>/dev/null; then
    exec uwsm-app -- bash -lc "$(printf 'cd %q && exec %q' "$cwd" "$term_bin")"
  fi

  case "$term" in
    kitty)
      exec kitty --directory="$cwd"
      ;;
    alacritty|Alacritty)
      exec alacritty --working-directory "$cwd"
      ;;
    foot)
      exec foot -D "$cwd"
      ;;
    wezterm)
      exec wezterm start --cwd "$cwd"
      ;;
    *)
      exec "$term_bin"
      ;;
  esac
}

main() {
  if ! _cwd_walk_enabled; then
    launch_terminal_plain
  fi

  command -v hyprctl &>/dev/null || { notify "hyprctl not found"; exit 1; }
  command -v jq &>/dev/null || { notify "jq not found"; exit 1; }

  local cwd
  if cwd=$(cwd_walk_resolve_focused); then
    launch_terminal "$cwd"
  fi

  local active_class
  active_class=$(hyprctl activewindow -j | jq -r '.class // empty')
  if [[ "${active_class,,}" == "thunar" ]]; then
    notify "Could not read Thunar folder — opening terminal at \$HOME"
  fi

  launch_terminal "$HOME"
}

main "$@"
