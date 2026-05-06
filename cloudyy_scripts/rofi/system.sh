#!/usr/bin/env bash
# =============================================================================
# system.sh — System Info & Process Menu
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# =============================================================================
# SYSTEM MENU
# =============================================================================

show_system_menu() {
  local uptime_str kernel
  uptime_str=$(uptime -p | sed 's/up //' || echo "Unknown")
  kernel=$(uname -r || echo "Unknown")

  local choice
  choice=$(menu "System" \
    "󰢮 System Info\n󰑐 Refresh\n󰿅 Process Killer\n󰘍 Back" \
    -mesg "Uptime: ${uptime_str} | Kernel: ${kernel}")

  case "${choice,,}" in
  *info*)
    command -v kitty &>/dev/null &&
      kitty -e sh -c "fastfetch 2>/dev/null || neofetch 2>/dev/null || echo 'No system info tool'; read -p 'Press Enter...'" &
    ;;
  *refresh*)
    show_system_menu
    ;;
  *killer*)
    command -v kitty &>/dev/null &&
      "hyprctl" kill
    ;;
  *) back_to_main ;;
  esac
}

# =============================================================================
# ENTRY POINT
# =============================================================================

show_system_menu
