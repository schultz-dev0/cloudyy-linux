#!/usr/bin/env bash
# Usage: timer_log.sh <label> <elapsed_seconds> <mode> [target_seconds]
set -euo pipefail

LABEL="$1"
ELAPSED_SECONDS="$2"
MODE="$3"
TARGET_SECONDS="${4:-0}"

RECORD_DIR="$HOME/Desktop/timer_record"
mkdir -p "$RECORD_DIR"

format_duration() {
    local secs=$1
    local h=$((secs / 3600))
    local m=$(( (secs % 3600) / 60 ))
    local s=$((secs % 60))
    if [ "$h" -gt 0 ]; then
        printf "%dh %02dm" "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf "%dm %02ds" "$m" "$s"
    else
        printf "%ds" "$s"
    fi
}

MONTH_FILE="$RECORD_DIR/$(date '+%Y-%m').md"
TODAY="$(date '+%Y-%m-%d')"
START_TIME="$(date '+%H:%M')"
DURATION="$(format_duration "$ELAPSED_SECONDS")"

if [ "$MODE" = "countdown" ] && [ "$TARGET_SECONDS" -gt 0 ]; then
    TARGET="$(format_duration "$TARGET_SECONDS")"
    MODE_LABEL="countdown ($TARGET)"
else
    MODE_LABEL="stopwatch"
fi

if [ ! -f "$MONTH_FILE" ]; then
    printf "# Timer Log — %s\n\n" "$(date '+%B %Y')" > "$MONTH_FILE"
fi

if ! grep -qF "## $TODAY" "$MONTH_FILE" 2>/dev/null; then
    printf "\n## %s\n\n| Started | Project | Duration | Mode |\n|---------|---------|----------|------|\n" \
        "$TODAY" >> "$MONTH_FILE"
fi

printf "| %s | %s | %s | %s |\n" "$START_TIME" "$LABEL" "$DURATION" "$MODE_LABEL" >> "$MONTH_FILE"
