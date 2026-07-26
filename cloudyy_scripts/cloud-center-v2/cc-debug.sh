#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cc-debug.sh — kill and restart QML Cloud Center with live log output
#
# Usage:
#   cc-debug.sh            — restart and follow logs
#   cc-debug.sh --kill     — kill only, do not restart
#   cc-debug.sh --log      — show logs of already-running instance (no restart)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

LAUNCHER="$HOME/cloudyy_scripts/cloud-center-v2/cloud-center"
CONFIG="$HOME/.config/quickshell/cloud-center"
LOG_FILE="/tmp/cloud-center-debug.log"

log()  { printf '\033[1;34m[cc-debug]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[cc-debug]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[cc-debug]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[cc-debug]\033[0m %s\n' "$*" >&2; }

cloud_center_pids() {
    unset __QUICKSHELL_CRASH_DUMP_PID __QUICKSHELL_CRASH_INFO_FD __QUICKSHELL_CRASH_SIGNAL || true
    qs list --all -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data if isinstance(data, list) else []:
    path = str(row.get("config_path") or "")
    if path.endswith("/cloud-center/shell.qml"):
        pid = row.get("pid")
        if pid is not None:
            print(pid)
' || true
}

kill_daemon() {
    local pids
    pids=$(cloud_center_pids)

    if [[ -n "$pids" ]]; then
        log "Sending SIGTERM to PIDs: $pids"
        kill -TERM $pids 2>/dev/null || true
        sleep 0.6

        pids=$(cloud_center_pids)
        if [[ -n "$pids" ]]; then
            warn "Still running — sending SIGKILL"
            kill -KILL $pids 2>/dev/null || true
            sleep 0.2
        fi
        ok "Killed."
    else
        warn "No running Cloud Center Quickshell instance found."
    fi
}

start_daemon() {
    if [[ ! -f "$LAUNCHER" ]]; then
        err "Launcher not found at: $LAUNCHER"
        exit 1
    fi

    log "Starting Cloud Center — logging to $LOG_FILE"
    log "Press Ctrl+C to stop following logs (app keeps running)"
    echo ""

    : > "$LOG_FILE"
    nohup "$LAUNCHER" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    ok "Launched via launcher (shell pid $pid)"
    echo ""
    tail -f "$LOG_FILE"
}

case "${1:-}" in
    --kill)
        kill_daemon
        ;;
    --log)
        if [[ ! -f "$LOG_FILE" ]]; then
            warn "No log file found at $LOG_FILE — has cloud-center been started via this script?"
            exit 1
        fi
        log "Following $LOG_FILE (Ctrl+C to stop)"
        tail -f "$LOG_FILE"
        ;;
    "")
        kill_daemon
        echo ""
        start_daemon
        ;;
    *)
        printf 'Usage: %s [--kill | --log]\n' "$0" >&2
        exit 1
        ;;
esac
