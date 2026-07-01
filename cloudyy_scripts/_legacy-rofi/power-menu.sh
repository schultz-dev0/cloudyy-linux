#!/usr/bin/env bash
# ==============================================================================
# ROFI POWER MENU STANDALONE (cuz its easier like this)
# ==============================================================================
# Dependencies: rofi, powerprofilesctl, systemctl, loginctl
# ==============================================================================

set -uo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# Icons
readonly ICON_LOCK="  Lock"
readonly ICON_LOGOUT="  Logout"
readonly ICON_SUSPEND="  Suspend"
readonly ICON_REBOOT="  Reboot"
readonly ICON_SHUTDOWN="  Shutdown"

readonly ICON_PERF="󰓅 "
readonly ICON_BAL="󱊥 "
readonly ICON_SAV=" "

# Commands
readonly CMD_POWERPROFILES="powerprofilesctl"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

centered_menu() {
  local prompt="$1"
  local options="$2"
  local mesg="${3:-}"

  local rofi_cmd=(
    rofi -dmenu -i -markup-rows -p "$prompt"
    -theme-str 'window { location: center; anchor: center; width: 450px; }'
    -theme-str 'listview { lines: 9; }'
    -theme-str 'element { padding: 12px; }'
    -theme-str 'element-text { font: "JetBrainsMono Nerd Font 12"; }'
  )

  # Add message if provided
  [[ -n "$mesg" ]] && rofi_cmd+=(-mesg "$mesg")

  printf "%b" "$options" | "${rofi_cmd[@]}"
}

get_battery_info() {
  # Default values if no battery found
  local cap="100"
  local status="AC"
  local icon=" "

  if [[ -d "/sys/class/power_supply/BAT0" ]]; then
    cap=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo "100")
    status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo "Unknown")

    # Dynamic Icon Logic
    if [[ "$status" == "Charging" ]]; then
      icon=""
    elif [[ "$cap" -ge 90 ]]; then
      icon=" "
    elif [[ "$cap" -ge 60 ]]; then
      icon=" "
    elif [[ "$cap" -ge 40 ]]; then
      icon=" "
    elif [[ "$cap" -ge 10 ]]; then
      icon=" "
    else icon=" "; fi
  fi

  echo "$icon $cap% ($status)"
}

# ==============================================================================
# MAIN LOGIC
# ==============================================================================

main() {
  # 1. Get Power Profile State
  local current_profile
  current_profile=$("$CMD_POWERPROFILES" get 2>/dev/null || echo "balanced")

  # Define Menu Options with Active Highlighting
  local opt_perf="$ICON_PERF Performance"
  local opt_bal="$ICON_BAL Balanced"
  local opt_sav="$ICON_SAV Power Saver"

  case "$current_profile" in
  performance) opt_perf="<b>$ICON_PERF Performance (Active)</b>" ;;
  balanced) opt_bal="<b>$ICON_BAL Balanced (Active)</b>" ;;
  power-saver) opt_sav="<b>$ICON_SAV Power Saver (Active)</b>" ;;
  esac

  # 2. Get Battery Info for Prompt
  local bat_info
  bat_info=$(get_battery_info)

  # 3. Build Menu
  # Note: The empty line "\n \n" creates a visual separator
  local options="$ICON_LOCK\n$ICON_SUSPEND\n$ICON_LOGOUT\n$ICON_REBOOT\n$ICON_SHUTDOWN\n \n$opt_perf\n$opt_bal\n$opt_sav"

  # 4. Show Menu
  local choice
  choice=$(centered_menu "Power" "$options" "Status: $bat_info")

  # 5. Handle Selection
  case "$choice" in
  "$ICON_LOCK")
    pidof hyprlock || hyprlock
    ;;
  "$ICON_SUSPEND")
    pidof hyprlock || hyprlock &
    systemctl suspend
    ;;
  "$ICON_LOGOUT")
    hyprctl dispatch exit
    ;;
  "$ICON_REBOOT")
    systemctl reboot
    ;;
  "$ICON_SHUTDOWN")
    systemctl poweroff
    ;;

  # Profile Switching
  *"Performance"*)
    "$CMD_POWERPROFILES" set performance
    notify-send "Power Profile" "Switched to Performance" -i power-profile-performance
    ;;
  *"Balanced"*)
    "$CMD_POWERPROFILES" set balanced
    notify-send "Power Profile" "Switched to Balanced" -i power-profile-balanced
    ;;
  *"Power Saver"*)
    "$CMD_POWERPROFILES" set power-saver
    notify-send "Power Profile" "Switched to Power Saver" -i power-profile-power-saver
    ;;
  *) back_to_main ;;
  esac
}

main "$@"
