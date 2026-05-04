#!/usr/bin/env bash
# =============================================================================
# learn.sh — Learn & Help Menu
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# =============================================================================
# KEYBIND TIPS  (launches keybinds.sh, returns here on close)
# =============================================================================

show_keybind_tips() {
  local script="${HOME}/cloudyy_scripts/rofi/keybinds.sh"
  [[ ! -x "$script" ]] && {
    notify-send "Error" "keybinds.sh not found at: $script"
    show_learn_menu
    return
  }
  # Subshell + || true so rofi escape never trips set -euo pipefail
  (bash "$script") || true
  show_learn_menu
}

show_browser_keybinds() {
  local script="${HOME}/cloudyy_scripts/rofi/browser-keybinds.sh"
  [[ ! -x "$script" ]] && {
    notify-send "Error" "browser-keybinds.sh not found at: $script"
    show_learn_menu
    return
  }
  (bash "$script") || true
  show_learn_menu
}

# =============================================================================
# LEARN MENU
# =============================================================================

show_learn_menu() {
  local choice
  choice=$(menu "Learn" \
    "󰣇 Arch Wiki\n Hyprland Wiki\n󱊨 Keybinds\n󰈹 Zen Binds")

  case "${choice,,}" in
  *arch*) run_app xdg-open "https://wiki.archlinux.org/" ;;
  *hypr*) run_app xdg-open "https://wiki.hypr.land/" ;;
  *zen*) show_browser_keybinds ;;
  *key*) show_keybind_tips ;;
  *) back_to_main ;;
  esac
}

# =============================================================================
# ENTRY POINT
# =============================================================================

show_learn_menu
