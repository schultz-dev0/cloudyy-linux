#!/usr/bin/env bash
# =============================================================================
# tools.sh — Tools Menu
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

show_tools_menu() {
  local choice
  choice=$(menu "Tools" \
    "󰆍 Live Text Extraction\n󰀲 LocalSend")

  case "$choice" in
  "󰆍 Live Text Extraction")
    exec "${HOME}/cloudyy_scripts/clipboard/text_extract.sh"
    ;;
  "󰀲 LocalSend")
    localsend &
    ;;
  *) back_to_main ;;
  esac
}

show_tools_menu
