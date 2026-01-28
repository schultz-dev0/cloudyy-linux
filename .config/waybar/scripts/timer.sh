#!/bin/bash

TIMER_FILE="/tmp/waybar_timer"

# Function to get current remaining time
get_remaining() {
    if [ -f "$TIMER_FILE" ]; then
        echo $(( $(cat "$TIMER_FILE") - $(date +%s) ))
    else
        echo 0
    fi
}

# Handle input arguments
case "$1" in
    add) # Add 5 minutes (300 seconds)
        REMAINING=$(get_remaining)
        NEW_TIME=$(( $(date +%s) + REMAINING + 300 ))
        echo "$NEW_TIME" > "$TIMER_FILE"
        ;;
    sub) # Subtract 5 minutes
        REMAINING=$(get_remaining)
        NEW_TIME=$(( $(date +%s) + REMAINING - 300 ))
        echo "$NEW_TIME" > "$TIMER_FILE"
        ;;
esac

# Display Logic
REMAINING=$(get_remaining)
if [ "$REMAINING" -gt 0 ]; then
    printf "󱎫 %02d:%02d:%02d\n" $((REMAINING/3600)) $((REMAINING%3600/60)) $((REMAINING%60))
else
    [ -f "$TIMER_FILE" ] && rm "$TIMER_FILE" && notify-send "Timer Finished" -u critical
    echo "󱎫 Off"
fi
