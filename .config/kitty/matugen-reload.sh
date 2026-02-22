#!/usr/bin/env bash
# ==============================================================================
# KITTY MATUGEN COLOR RELOAD
# Hot-swaps colors into all running kitty windows via remote control.
# Does NOT close or restart kitty — all sessions stay alive.
#
# Requirements in kitty.conf:
#   allow_remote_control yes
#   listen_on unix:/tmp/kitty
#
# Place in: ~/.config/kitty/matugen-reload.sh
# Matugen config.toml post_hook: '~/.config/kitty/matugen-reload.sh'
# ==============================================================================

set -euo pipefail

readonly COLORS_FILE="${HOME}/.config/matugen/generated/kitty-colors.conf"
readonly SOCKET="/tmp/kitty"

log()  { printf '[kitty-reload] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

# --- Checks ---
[[ -f "$COLORS_FILE" ]] || fail "Color file not found: $COLORS_FILE (has matugen run yet?)"
command -v kitty >/dev/null 2>&1 || fail "kitty not found in PATH"

# --- Check if kitty is running with remote control ---
if ! pgrep -x kitty >/dev/null 2>&1; then
    log "No running kitty instance — skipping reload"
    exit 0
fi

# --- Apply colors via remote control ---
if [[ -S "$SOCKET" ]]; then
    log "Applying colors via remote control socket..."
    if kitty @ --to "unix:${SOCKET}" set-colors --all --configured "$COLORS_FILE" 2>/dev/null; then
        log "Colors applied to all windows"
        exit 0
    else
        log "Remote control failed — falling back to SIGUSR1"
    fi
else
    log "Socket $SOCKET not found — falling back to SIGUSR1"
    log "To enable remote control, add to kitty.conf:"
    log "  allow_remote_control yes"
    log "  listen_on unix:${SOCKET}"
fi

# --- Fallback: SIGUSR1 reloads kitty.conf (requires include of colors file) ---
pkill -SIGUSR1 kitty 2>/dev/null || true
log "SIGUSR1 sent (config reload)"
