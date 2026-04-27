#!/usr/bin/env bash
# ==============================================================================
# widget_bridge.sh — Wires the correct bridge script into theme_controller.sh
# ==============================================================================
# Usage: ./widget_bridge.sh <profile_name>
# Profiles: default, quickshell
# ==============================================================================

set -euo pipefail

PROFILE="${1:-quickshell}"
THEME_CONTROLLER_HOME="${HOME}/cloudyy_scripts/theme_controller.sh"
# Also patch the repo version during install if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_CONTROLLER_REPO="$(cd "$SCRIPT_DIR/.." && pwd)/cloudyy_scripts/theme_controller.sh"

BRIDGE_SCRIPT="${HOME}/cloudyy_scripts/bridge_scripts/bridge_${PROFILE}.sh"

update_controller() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Update the WIDGETS_BRIDGE variable
        sed -i "s|^WIDGETS_BRIDGE=.*|WIDGETS_BRIDGE=\"${BRIDGE_SCRIPT}\"|" "$file"
        echo "[✓] Wired ${PROFILE} bridge into $(basename "$file")"
    fi
}

update_controller "$THEME_CONTROLLER_HOME"
update_controller "$THEME_CONTROLLER_REPO"

# --- update cloud-center.py wiring -------------------------------------------
update_cloud_center() {
    local py_file="$1"
    if [[ -f "$py_file" ]]; then
        local tab="waybar"
        [[ "$PROFILE" == "quickshell" ]] && tab="quickshell"
        
        sed -i "s|^ACTIVE_SHELL_TAB = \".*\"|ACTIVE_SHELL_TAB = \"$tab\"|" "$py_file"
        echo "[✓] Wired ${PROFILE} tab into $(basename "$py_file")"
    fi
}

update_cloud_center "${HOME}/cloudyy_scripts/cloud-center-v2/cloud-center.py"
update_cloud_center "$(cd "$SCRIPT_DIR/.." && pwd)/cloudyy_scripts/cloud-center-v2/cloud-center.py"
