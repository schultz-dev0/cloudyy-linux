#!/usr/bin/env bash
# ==============================================================================
# QUICKSHELL SHELL STACK BRIDGE
# Handles reloading for Quickshell.
# Managed by cloudyy-linux installer.
# ==============================================================================

log_info() { printf '\033[1;34m[BRIDGE]\033[0m %s\n' "$*" >&2; }

# Cross-stack Cleanup: Kill Waybar and SwayNC
pkill -x waybar || true
pkill -x swaync || true

# Wait to ensure they are dead (max 2 seconds)
for ((i=0; i<20; i++)); do
    if ! pgrep -x "waybar|swaync" >/dev/null; then
        break
    fi
    sleep 0.1
done

# Force kill if still hanging
if pgrep -x "waybar|swaync" >/dev/null; then
    pkill -9 -x "waybar|swaync" || true
fi

# Start Quickshell as a daemon only if it's not already running.
# The -n flag (no-duplicate) ensures that if Quickshell is already active,
# this command exits silently, allowing the existing instance to hot-reload
# its colors naturally when matugen updates Theme.qml.
if command -v qs >/dev/null 2>&1; then
    PRESET_FILE="${HOME}/.config/quickshell/.current_preset"
    PRESET="macos"
    [[ -f "$PRESET_FILE" ]] && PRESET="$(cat "$PRESET_FILE" | tr -d '[:space:]')"
    
    qs -c "$PRESET" -n -d
else
    # Fallback to pgrep check if using the raw binary name
    if ! pgrep -x quickshell >/dev/null; then
        quickshell -d 2>/dev/null || true
    fi
fi

# [Reserved for other quickshell-integrated components or future triggers]
