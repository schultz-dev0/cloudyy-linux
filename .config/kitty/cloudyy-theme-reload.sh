#!/usr/bin/env bash

# Hot-load the active curated Cloudyy palette without closing Kitty sessions.

set -euo pipefail

readonly COLORS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/current-theme.conf"
readonly SOCKET="/tmp/kitty"

log() { printf '[kitty-theme-reload] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

[[ -f "$COLORS_FILE" ]] || fail "Color file not found: $COLORS_FILE"
command -v kitty >/dev/null 2>&1 || fail "kitty not found in PATH"

if ! pgrep -x kitty >/dev/null 2>&1; then
  log "No running Kitty instance — skipping reload"
  exit 0
fi

if [[ -S "$SOCKET" ]] &&
  kitty @ --to "unix:${SOCKET}" set-colors --all --configured "$COLORS_FILE" 2>/dev/null; then
  log "Colors applied to all Kitty windows"
  exit 0
fi

pkill -SIGUSR1 -x kitty >/dev/null 2>&1 || fail "Kitty configuration reload failed"
log "Kitty configuration reloaded"
