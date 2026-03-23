#!/usr/bin/env bash
set -euo pipefail

APP_ID="dev.cloudyy.CloudCenter"
SCRIPT="$HOME/cloudyy_scripts/cloud-center-v2/cloud-center.py"
LOG_FILE="/tmp/cloud-center.log"

log() {
    printf '[cc-restart] %s\n' "$*"
}

running_pids() {
    pgrep -f "cloud-center.py" 2>/dev/null || true
}

has_visible_window() {
    command -v hyprctl >/dev/null 2>&1 || return 0

    hyprctl clients -j 2>/dev/null | python3 -c '
import json
import sys

raw = sys.stdin.read().strip()
if not raw:
    print("0")
    raise SystemExit(0)

try:
    clients = json.loads(raw)
except Exception:
    print("0")
    raise SystemExit(0)

def norm(v):
    return str(v or "").strip().lower()

for c in clients:
    cls = norm(c.get("class") or c.get("initialClass"))
    title = norm(c.get("title") or c.get("initialTitle"))
    mapped = bool(c.get("mapped", True))
    hidden = bool(c.get("hidden", False))

    if "cloudcenter" in cls or "cloud-center" in cls or "cloud center" in title:
        if mapped and not hidden:
            print("1")
            raise SystemExit(0)

print("0")
'
}

stop_cloud_center() {
    local pids

    # Prefer the app-level quit so GTK can close cleanly.
    gdbus call \
        --session \
        --dest "$APP_ID" \
        --object-path /dev/cloudyy/CloudCenter \
        --method org.gtk.Application.Quit \
        >/dev/null 2>&1 || true

    sleep 0.5

    pids="$(running_pids)"
    if [[ -z "$pids" ]]; then
        return 0
    fi

    kill -TERM $pids 2>/dev/null || true
    sleep 0.8

    pids="$(running_pids)"
    if [[ -n "$pids" ]]; then
        kill -KILL $pids 2>/dev/null || true
        sleep 0.3
    fi
}

start_cloud_center() {
    local background="${1:-0}"

    if [[ ! -f "$SCRIPT" ]]; then
        log "Cloud Center script not found: $SCRIPT"
        exit 1
    fi

    : > "$LOG_FILE"

    if command -v uwsm-app >/dev/null 2>&1; then
        if [[ "$background" == "1" ]]; then
            nohup uwsm-app -- python3 "$SCRIPT" --background >>"$LOG_FILE" 2>&1 &
        else
            nohup uwsm-app -- python3 "$SCRIPT" >>"$LOG_FILE" 2>&1 &
        fi
    else
        if [[ "$background" == "1" ]]; then
            nohup python3 "$SCRIPT" --background >>"$LOG_FILE" 2>&1 &
        else
            nohup python3 "$SCRIPT" >>"$LOG_FILE" 2>&1 &
        fi
    fi

    disown || true
}

background_restart=0
if [[ -n "$(running_pids)" ]]; then
    if [[ "$(has_visible_window)" == "0" ]]; then
        background_restart=1
    fi
fi

stop_cloud_center
start_cloud_center "$background_restart"

if [[ "$background_restart" == "1" ]]; then
    log "Cloud Center silently restarted in background. Log: $LOG_FILE"
else
    log "Cloud Center restarted. Log: $LOG_FILE"
fi
