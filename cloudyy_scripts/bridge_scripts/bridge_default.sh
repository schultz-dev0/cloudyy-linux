#!/usr/bin/env bash
# ==============================================================================
# DEFAULT SHELL STACK BRIDGE
# Handles reloading for Waybar + SwayNC.
# Managed by cloudyy-linux installer.
# ==============================================================================

# Handle Waybar
# launch_waybar.sh already handles pkill, polling, and clean restart.
if [[ -x "$HOME/cloudyy_scripts/waybar/launch_waybar.sh" ]]; then
    "$HOME/cloudyy_scripts/waybar/launch_waybar.sh" &
else
    pkill -x waybar || true
    sleep 0.1
    waybar &
fi

# Handle SwayNC
pkill -x swaync || true
sleep 0.1
swaync &

# Cross-stack Cleanup: Ensure Quickshell is dead
if command -v qs >/dev/null 2>&1; then
    qs kill >/dev/null 2>&1 || true
else
    pkill -x quickshell || true
fi

# [Reserved for other components converted to quickshell later]
