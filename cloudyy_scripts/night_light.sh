#!/usr/bin/env bash

# ==============================================================================
# NIGHT LIGHT TOGGLE SCRIPT (With Auto-Install)
# ==============================================================================

# 1. Configuration
TEMP_LOW=4000
TEMP_HIGH=6500
TERMINAL="kitty" # <--- CHANGE THIS if you use alacritty, foot, or wezterm

# 2. Dependency Check & Auto-Install
if ! command -v wlsunset &>/dev/null; then
  notify-send -u critical -a "System" "Missing Dependency" "Installing wlsunset..."

  # Open a terminal to ask for sudo password
  $TERMINAL --title "Installer" -e sh -c "sudo pacman -S --noconfirm wlsunset; echo 'Done! Closing...'; sleep 1"

  # verification
  if ! command -v wlsunset &>/dev/null; then
    notify-send -u critical -a "System" "Installation Failed" "Please install wlsunset manually."
    exit 1
  fi
fi

# 3. Main Toggle Logic
if pgrep -x "wlsunset" >/dev/null; then
  pkill wlsunset
  notify-send -r 555 -a "Display" "Night Light" "Disabled " -t 2000
else
  wlsunset -t $TEMP_LOW -T $TEMP_HIGH &
  notify-send -r 555 -a "Display" "Night Light" "Enabled " -t 2000
fi
