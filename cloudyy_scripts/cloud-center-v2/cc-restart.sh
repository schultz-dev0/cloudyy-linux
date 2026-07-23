#!/usr/bin/env bash
set -euo pipefail

# Restart the QML Cloud Center Quickshell instance after theme changes.
# Set CC_DISABLE_RESTART=1 to temporarily disable this script.
if [[ "${CC_DISABLE_RESTART:-0}" == "1" ]]; then
    printf '[cc-restart] disabled (CC_DISABLE_RESTART=1)\n'
    exit 0
fi

LAUNCHER="$HOME/cloudyy_scripts/cloud-center"
CONFIG="$HOME/.config/quickshell/cloud-center"
LOG_FILE="/tmp/cloud-center.log"

log() {
    printf '[cc-restart] %s\n' "$*"
}

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

has_visible_window() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    local pid="$1"
    [[ -n "$pid" ]] || return 1
    # Prefer JSON clients; fall back if jq missing.
    if command -v jq >/dev/null 2>&1; then
        hyprctl -j clients 2>/dev/null | jq -e --arg pid "$pid" \
            '.[] | select(.class=="org.quickshell" and (.pid|tostring)==$pid)' >/dev/null 2>&1
        return $?
    fi
    return 0
}

stop_cloud_center() {
    local pids
    pids="$(cloud_center_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    log "Stopping Cloud Center PIDs: $pids"
    kill -TERM $pids 2>/dev/null || true
    sleep 0.5

    pids="$(cloud_center_pids)"
    if [[ -n "$pids" ]]; then
        kill -KILL $pids 2>/dev/null || true
        sleep 0.2
    fi
}

start_cloud_center() {
    if [[ ! -x "$LAUNCHER" && ! -f "$LAUNCHER" ]]; then
        log "Cloud Center launcher not found: $LAUNCHER"
        exit 1
    fi

    : > "$LOG_FILE"

    if command -v uwsm-app >/dev/null 2>&1; then
        nohup uwsm-app -- "$LAUNCHER" >>"$LOG_FILE" 2>&1 &
    else
        nohup "$LAUNCHER" >>"$LOG_FILE" 2>&1 &
    fi
    disown || true
}

pids="$(cloud_center_pids)"
if [[ -z "$pids" ]]; then
    log "Cloud Center is not running — skipping restart."
    exit 0
fi

# Remember whether a window was visible so we can log intent; QML always
# reopens a window on launch (no GTK --background equivalent).
visible=0
for pid in $pids; do
    if has_visible_window "$pid"; then
        visible=1
        break
    fi
done

stop_cloud_center
start_cloud_center

if [[ "$visible" == "1" ]]; then
    log "Cloud Center restarted. Log: $LOG_FILE"
else
    log "Cloud Center restarted (was window-less). Log: $LOG_FILE"
fi
