#!/usr/bin/env bash
# =============================================================================
# main.sh — Cloudyy Dashboard (Entry Point)
# All submenus live in ~/cloudyy_scripts/rofi/
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================

if ! command -v rofi &>/dev/null; then
  notify-send "Error" "rofi is not installed"
  exit 1
fi

if [[ ! -x "$THEME_CTL" ]]; then
  notify-send "Error" "Theme controller not found: $THEME_CTL"
  exit 1
fi

init_dirs

# =============================================================================
# MAIN MENU
# =============================================================================

show_main_menu() {
  local choice
  choice=$(menu "Dashboard" \
    "󰧑 Learn\n󰈈 Appearance\n󰀻 Applications\n󰹑 System\n CloudCenter\n󰏖 Packages\n󰚩 AI\n󰐥 Power")

  case "$choice" in
  "󰧑 Learn") exec "${ROFI_DIR}/learn.sh" ;;
  "󰈈 Appearance") exec "${ROFI_DIR}/appearance.sh" ;;
  "󰀻 Applications") exec "${ROFI_DIR}/applications.sh" ;;
  "󰹑 System") exec "${ROFI_DIR}/system.sh" ;;
  " CloudCenter") hyprctl dispatch exec \ "python3 ${HOME}/cloudyy_scripts/cloud-center-v2/cloud-center.py" ;;
  "󰏖 Packages") exec "${ROFI_DIR}/packages.sh" ;;
  "󰚩 AI") exec "${ROFI_DIR}/ai.sh" ;;
  "󰐥 Power") exec "${HOME}/cloudyy_scripts/rofi/power-menu.sh" ;;
  *) exit 0 ;;
  esac
}

# =============================================================================
# CLI SHORTCUTS  (e.g. keybind: main.sh --appearance)
# =============================================================================

main() {
  if [[ -n "${1:-}" ]]; then
    case "$1" in
    --random) run_app "$THEME_CTL" random ;;
    --next) run_app "$THEME_CTL" next ;;
    --toggle) run_app "$THEME_CTL" toggle ;;
    --select) exec "${ROFI_DIR}/appearance.sh" --select ;;
    --appearance) exec "${ROFI_DIR}/appearance.sh" ;;
    --applications) exec "${ROFI_DIR}/applications.sh" ;;
    --packages) exec "${ROFI_DIR}/packages.sh" ;;
    *) show_main_menu ;;
    esac
  else
    show_main_menu
  fi
}

main "$@"
