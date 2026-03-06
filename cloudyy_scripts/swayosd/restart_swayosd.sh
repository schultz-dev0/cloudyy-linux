#!/usr/bin/env bash
# restart_swayosd.sh — restart swayosd-server
# Use as matugen post_command:
#   post_command = "$HOME/cloudyy_scripts/restart_swayosd.sh"

set -euo pipefail

readonly BIN="swayosd-server"
readonly GRACE=10
readonly GRACE_SLEEP=0.1
readonly SETTLE=0.3

_running() { pgrep -x "$BIN" >/dev/null 2>&1; }

# ── Shutdown ──────────────────────────────────────────────────────────────────
if _running; then
  pkill -x "$BIN" 2>/dev/null || true
  for ((i = 0; i < GRACE; i++)); do
    _running || break
    sleep "$GRACE_SLEEP"
  done
  if _running; then
    pkill -9 -x "$BIN" 2>/dev/null || true
    sleep 0.1
  fi
fi

# ── Startup ───────────────────────────────────────────────────────────────────
# uwsm-app is preferred since you're running UWSM under Hyprland —
# it places the process in the correct systemd user session scope.
if command -v uwsm-app >/dev/null 2>&1; then
  uwsm-app -- "$BIN" >/dev/null 2>&1 &
else
  setsid "$BIN" >/dev/null 2>&1 &
fi
disown 2>/dev/null || true

# ── Verify ────────────────────────────────────────────────────────────────────
sleep "$SETTLE"
if _running; then
  echo "swayosd-server restarted OK"
else
  echo "swayosd-server failed to start" >&2
  exit 1
fi
