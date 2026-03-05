#!/usr/bin/env bash
# =============================================================================
# lib/common.sh — Shared config & utilities for all rofi menu scripts
# Source this file at the top of every menu script:
#   source "${ROFI_DIR}/lib/common.sh"
# =============================================================================

# --- PATHS ---
readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
readonly THEME_CTL="${HOME}/cloudyy_scripts/theme_controller.sh"
readonly HKBM_CMD="${HOME}/cloudyy_scripts/cloudyy-other/hkbm"
readonly HCM_CMD="${HOME}/cloudyy_scripts/cloudyy-other/hcm"
readonly BASE_WALL_DIR="${HOME}/Wallpapers"
readonly CACHE_DIR="${HOME}/.cache/rofi_thumbs"

# --- WALLPAPER THUMB SETTINGS ---
readonly THUMB_SIZE=250
readonly MAX_JOBS=$(nproc)
readonly TEMP_INPUT="/tmp/rofi_input_$$"

trap 'rm -f "$TEMP_INPUT"' EXIT INT TERM

# --- ROFI DEFAULTS ---
readonly ROFI_CMD=(rofi -dmenu -i)

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

init_dirs() {
    mkdir -p "$CACHE_DIR" "$BASE_WALL_DIR"
}

# Standard dmenu prompt with optional preselect
menu() {
    local prompt="$1"
    local options="$2"
    local extra_args=("${@:3}")
    printf "%b" "$options" | "${ROFI_CMD[@]}" -p "$prompt" "${extra_args[@]}"
}

# Centred floating menu (confirmations, etc.)
centered_menu() {
    local prompt="$1"
    local options="$2"
    printf "%b" "$options" | rofi -dmenu -i -p "$prompt" \
        -theme-str 'window { location: center; anchor: center; width: 450px; }' \
        -theme-str 'listview { lines: 8; }' \
        -theme-str 'element { padding: 12px; }' \
        -theme-str 'element-text { font: "JetBrainsMono Nerd Font 12"; }'
}

# Fire-and-forget launcher via uwsm
run_app() {
    nohup uwsm-app -- "$@" >/dev/null 2>&1 &
    disown
}

# Return to the main dashboard
back_to_main() {
    exec "${ROFI_DIR}/main.sh"
}

# =============================================================================
# THEME / MODE HELPERS
# =============================================================================

get_current_mode() {
    local raw_mode
    raw_mode=$("$THEME_CTL" get-mode 2>/dev/null || echo "dark")
    raw_mode=$(echo "$raw_mode" | tr -d '[:space:]')
    [[ "$raw_mode" != "light" && "$raw_mode" != "dark" ]] && raw_mode="dark"
    echo "$raw_mode"
}
