#!/usr/bin/env bash
# ~/cloudyy_scripts/sliders/nightlight.sh
# Expects a normal user session (systemctl --user, hyprctl) — do not run via hyprctl dispatch exec.
#
# Toggle OFF uses `hyprctl hyprsunset identity` — do not stop/kill hyprsunset.
# Killing the daemon can destabilize Hyprland and take down terminals / Electron apps.

HYPRCTL=(hyprctl)
command -v hyprctl >/dev/null 2>&1 || HYPRCTL=(/usr/bin/hyprctl)

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
TEMP_FILE="${CACHE_DIR}/wltemp"
ACTIVE_FILE="${CACHE_DIR}/wlnight_active"

apply_ipc() {
    local subcmd=$1
    shift
    local i
    for i in {1..35}; do
        if "${HYPRCTL[@]}" hyprsunset "$subcmd" "$@" 2>/dev/null; then
            return 0
        fi
        sleep 0.12
    done
    return 1
}

apply_temp() {
    apply_ipc temperature "$1"
}

apply_identity() {
    apply_ipc identity
}

hyprsunset_running() {
    pgrep -x hyprsunset >/dev/null 2>&1
}

nightlight_active() {
    [[ -f "$ACTIVE_FILE" ]] && [[ "$(tr '[:upper:]' '[:lower:]' < "$ACTIVE_FILE")" == "true" ]]
}

ensure_hyprsunset() {
    hyprsunset_running && return 0
    systemctl --user start hyprsunset.service 2>/dev/null || hyprsunset >/dev/null 2>&1 &
    local i
    for i in {1..40}; do
        hyprsunset_running && return 0
        sleep 0.1
    done
    return 1
}

set_active_flag() {
    mkdir -p "$CACHE_DIR"
    printf '%s\n' "$1" >"$ACTIVE_FILE"
}

enable_nightlight() {
    local temp="${1:-3500}"
    mkdir -p "$CACHE_DIR"
    ensure_hyprsunset || return 1
    sleep 0.15
    apply_temp "$temp" || return 1
    printf '%s' "$temp" >"$TEMP_FILE"
    set_active_flag true
}

disable_nightlight() {
    if hyprsunset_running; then
        apply_identity || true
    fi
    set_active_flag false
}

case "$1" in
    toggle)
        if nightlight_active; then
            disable_nightlight
        else
            TEMP=$(cat "$TEMP_FILE" 2>/dev/null || echo 3500)
            enable_nightlight "$TEMP" || true
        fi
        ;;
    set)
        TEMP="${2:-3500}"
        mkdir -p "$CACHE_DIR"
        printf '%s' "$TEMP" >"$TEMP_FILE"
        if nightlight_active; then
            ensure_hyprsunset || true
            sleep 0.1
            apply_temp "$TEMP" || true
        fi
        ;;
esac
