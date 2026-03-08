#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# cc-debug.sh — kill and restart Cloud Center daemon with live log output
#
# Usage:
#   cc-debug.sh            — restart and follow logs
#   cc-debug.sh --kill     — kill only, do not restart
#   cc-debug.sh --log      — show logs of already-running instance (no restart)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

APP_ID="dev.cloudyy.CloudCenter"
SCRIPT="$HOME/cloudyy_scripts/cloud-center-v2/cloud-center.py"
LOG_FILE="/tmp/cloud-center-debug.log"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { printf '\033[1;34m[cc-debug]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[cc-debug]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[cc-debug]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[cc-debug]\033[0m %s\n' "$*" >&2; }

kill_daemon() {
    # Try graceful D-Bus quit first, then SIGTERM, then SIGKILL
    if gdbus call \
        --session \
        --dest "$APP_ID" \
        --object-path /dev/cloudyy/CloudCenter \
        --method org.gtk.Application.Quit \
        2>/dev/null; then
        log "Sent D-Bus quit signal"
        sleep 0.5
    fi

    local pids
    pids=$(pgrep -f "cloud-center.py" 2>/dev/null || true)

    if [[ -n "$pids" ]]; then
        log "Sending SIGTERM to PIDs: $pids"
        kill -TERM $pids 2>/dev/null || true
        sleep 0.8

        # Check if still alive
        pids=$(pgrep -f "cloud-center.py" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            warn "Still running — sending SIGKILL"
            kill -KILL $pids 2>/dev/null || true
            sleep 0.3
        fi
        ok "Killed."
    else
        warn "No running cloud-center.py found."
    fi
}

start_daemon() {
    if [[ ! -f "$SCRIPT" ]]; then
        err "Script not found at: $SCRIPT"
        err "Edit SCRIPT= at the top of this file to point at your cloud-center.py"
        exit 1
    fi

    log "Starting Cloud Center — logging to $LOG_FILE"
    log "Press Ctrl+C to stop following logs (daemon keeps running)"
    echo ""

    # Truncate log so we only see output from this run
    : > "$LOG_FILE"

    # Launch detached, stdout+stderr → log file
    nohup python3 "$SCRIPT" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    ok "Launched PID $pid"
    echo ""

    # Follow the log
    tail -f "$LOG_FILE"
}

# ── Argument handling ─────────────────────────────────────────────────────────

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
