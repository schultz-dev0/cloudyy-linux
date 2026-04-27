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
