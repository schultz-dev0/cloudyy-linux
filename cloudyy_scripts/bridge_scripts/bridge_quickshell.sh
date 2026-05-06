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
# We use a lockfile to prevent race conditions during rapid wallpaper changes.
LOCKFILE="/tmp/quickshell_bridge.lock"

(
  flock -n 9 || exit 0 # If another bridge is already running, just exit.

  if command -v qs >/dev/null 2>&1; then
      # The -n flag (no-duplicate) ensures that if Quickshell is already active,
      # this command exits silently.
      # We explicitly close FD 9 to prevent the daemon from inheriting the lock.
      env QS_NO_RELOAD_POPUP=1 qs -n -d 9>&-
  else
      # Fallback to pgrep check if using the raw binary name
      if ! pgrep -x quickshell >/dev/null; then
          env QS_NO_RELOAD_POPUP=1 quickshell -d 9>&- 2>/dev/null || true
      fi
  fi
) 9>"$LOCKFILE"

# [Reserved for other quickshell-integrated components or future triggers]
