#!/usr/bin/env bash
# ~/cloudyy_scripts/sliders/nightlight.sh
# Expects a normal user session (systemctl --user, hyprctl) — do not run via hyprctl dispatch exec.

HYPRCTL=(hyprctl)
command -v hyprctl >/dev/null 2>&1 || HYPRCTL=(/usr/bin/hyprctl)

apply_temp() {
    local temp="$1"
    local i
    for i in {1..35}; do
        if "${HYPRCTL[@]}" hyprsunset temperature "$temp" 2>/dev/null; then
            return 0
        fi
        sleep 0.12
    done
    return 1
}

case "$1" in
    toggle)
        if systemctl --user is-active hyprsunset.service >/dev/null 2>&1 || pgrep -x hyprsunset >/dev/null; then
            systemctl --user stop hyprsunset.service 2>/dev/null || true
            pkill -x hyprsunset 2>/dev/null || true
        else
            TEMP=$(cat "${XDG_CACHE_HOME:-$HOME/.cache}/wltemp" 2>/dev/null || echo 3500)

            if ! systemctl --user start hyprsunset.service 2>/dev/null; then
                hyprsunset >/dev/null 2>&1 &
            fi

            for i in {1..40}; do
                if pgrep -x hyprsunset >/dev/null; then
                    sleep 0.15
                    apply_temp "$TEMP" || true
                    break
                fi
                sleep 0.1
            done

            mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
            printf '%s' "$TEMP" >"${XDG_CACHE_HOME:-$HOME/.cache}/wltemp"
        fi
        ;;
    set)
        TEMP="${2:-3500}"
        mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
        printf '%s' "$TEMP" >"${XDG_CACHE_HOME:-$HOME/.cache}/wltemp"
        if pgrep -x hyprsunset >/dev/null; then
            apply_temp "$TEMP" || true
        fi
        ;;
esac
