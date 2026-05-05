#!/usr/bin/env bash
# ==============================================================================
# widget_bridge.sh — Wires the quickshell bridge into theme_controller.sh
# ==============================================================================

set -euo pipefail

THEME_CONTROLLER_HOME="${HOME}/cloudyy_scripts/theme_controller.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_CONTROLLER_REPO="$(cd "$SCRIPT_DIR/.." && pwd)/cloudyy_scripts/theme_controller.sh"
BRIDGE_SCRIPT="${HOME}/cloudyy_scripts/bridge_scripts/bridge_quickshell.sh"

verify_controller_bridge() {
    local file="$1"
    if grep -Fxq "WIDGETS_BRIDGE=\"${BRIDGE_SCRIPT}\"" "$file"; then
        echo "[✓] Wired quickshell bridge into $(basename "$file")"
    else
        echo "[✗] Failed to wire quickshell bridge into $(basename "$file")" >&2
        exit 1
    fi
}

update_controller() {
    local file="$1"
    if [[ -f "$file" ]]; then
        sed -i "s|^WIDGETS_BRIDGE=.*|WIDGETS_BRIDGE=\"${BRIDGE_SCRIPT}\"|" "$file"
        verify_controller_bridge "$file"
    fi
}

update_controller "$THEME_CONTROLLER_HOME"
update_controller "$THEME_CONTROLLER_REPO"

# --- update cloud-center.py wiring -------------------------------------------
verify_cloud_center() {
    local py_file="$1"
    if grep -Fxq 'ACTIVE_SHELL_TAB = "quickshell"' "$py_file"; then
        echo "[✓] Wired quickshell tab into $(basename "$py_file")"
    else
        echo "[✗] Failed to wire quickshell tab into $(basename "$py_file")" >&2
        exit 1
    fi
}

update_cloud_center() {
    local py_file="$1"
    if [[ -f "$py_file" ]]; then
        sed -i 's|^ACTIVE_SHELL_TAB = ".*"|ACTIVE_SHELL_TAB = "quickshell"|' "$py_file"
        verify_cloud_center "$py_file"
    fi
}

update_cloud_center "${HOME}/cloudyy_scripts/cloud-center-v2/cloud-center.py"
update_cloud_center "$(cd "$SCRIPT_DIR/.." && pwd)/cloudyy_scripts/cloud-center-v2/cloud-center.py"
