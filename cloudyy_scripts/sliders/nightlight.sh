#!/usr/bin/env bash
# ~/cloudyy_scripts/sliders/nightlight.sh

case "$1" in
    toggle)
        # Check if service is active OR if process is running manually
        if systemctl --user is-active hyprsunset.service >/dev/null 2>&1 || pgrep -x hyprsunset >/dev/null; then
            # Stop everything
            systemctl --user stop hyprsunset.service 2>/dev/null
            pkill -x hyprsunset 2>/dev/null
        else
            TEMP=$(cat "$HOME/.cache/wltemp" 2>/dev/null || echo 3500)
            
            # Start service, or binary if service fails
            if ! systemctl --user start hyprsunset.service 2>/dev/null; then
                hyprsunset >/dev/null 2>&1 &
            fi
            
            # Wait for readiness
            for i in {1..20}; do
                if pgrep -x hyprsunset >/dev/null; then
                    sleep 0.2
                    hyprctl hyprsunset temperature "$TEMP" 2>/dev/null && break
                fi
                sleep 0.1
            done
            
            mkdir -p "$HOME/.cache"
            printf "%s" "$TEMP" > "$HOME/.cache/wltemp"
        fi
        ;;
    set)
        TEMP="${2:-3500}"
        mkdir -p "$HOME/.cache"
        printf "%s" "$TEMP" > "$HOME/.cache/wltemp"
        if pgrep -x hyprsunset >/dev/null; then
            hyprctl hyprsunset temperature "$TEMP" 2>/dev/null || true
        fi
        ;;
esac
