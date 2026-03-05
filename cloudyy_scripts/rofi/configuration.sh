#!/usr/bin/env bash
# =============================================================================
# configuration.sh — Config & Keybind Manager Menu
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# =============================================================================
# CONFIGURATION MENU
# =============================================================================

show_configuration_menu() {
  local choice
  choice=$(menu "Configuration" \
    "󱊨 Keybinds\n Configs")

  case "${choice,,}" in
  *keybind*)
    [[ ! -x "$HKBM_CMD" ]] && {
      notify-send "Error" "hkbm not found at: $HKBM_CMD"
      show_configuration_menu
      return
    }
    nohup kitty --title "Keybind Manager" -e "$HKBM_CMD" >/dev/null 2>&1 &
    disown
    ;;
  *config*)
    [[ ! -x "$HCM_CMD" ]] && {
      notify-send "Error" "hcm not found at: $HCM_CMD"
      show_configuration_menu
      return
    }
    nohup kitty --title "Config Manager" -e "$HCM_CMD" >/dev/null 2>&1 &
    disown
    ;;
  *) back_to_main ;;
  esac
}

# =============================================================================
# ENTRY POINT
# =============================================================================

show_configuration_menu
