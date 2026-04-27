#!/usr/bin/env bash
# ==============================================================================
# DEFAULT SHELL STACK BRIDGE
# Handles reloading for Waybar + SwayNC.
# Managed by cloudyy-linux installer.
# ==============================================================================

LOCKFILE="/tmp/default_bridge.lock"

# Use flock on a subshell but ensure background processes are detached
(
  flock -n 9 || exit 0 # Exit if another bridge is already handling the restart.

  # Cross-stack Cleanup: Ensure Quickshell is dead
  if command -v qs >/dev/null 2>&1; then
      qs kill >/dev/null 2>&1 || true
  fi
  pkill -9 -x quickshell 2>/dev/null || true
  pkill -9 -x qs 2>/dev/null || true

  # Handle Waybar
  # launch_waybar.sh already handles pkill, polling, and clean restart.
  if [[ -x "$HOME/cloudyy_scripts/waybar/launch_waybar.sh" ]]; then
      # Close FD 9 explicitly to prevent lock inheritance
      "$HOME/cloudyy_scripts/waybar/launch_waybar.sh" 9>&- &
  else
      pkill -x waybar || true
      sleep 0.1
      waybar 9>&- &
  fi

  # Handle SwayNC
  pkill -x swaync || true
  sleep 0.1
  swaync 9>&- &

) 9>"$LOCKFILE"

# [Reserved for other components converted to quickshell later]
