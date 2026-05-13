#!/usr/bin/env bash
# ==============================================================================
# widget_bridge.sh — Wires the quickshell bridge into theme_controller.sh
# ==============================================================================

set -euo pipefail

THEME_CONTROLLER_HOME="${HOME}/cloudyy_scripts/theme_controller.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_CONTROLLER_REPO="$(cd "$SCRIPT_DIR/.." && pwd)/cloudyy_scripts/theme_controller.sh"
BRIDGE_SCRIPT="${HOME}/cloudyy_scripts/bridge_scripts/bridge_quickshell.sh"
CLOUD_CENTER_HOME="${HOME}/cloudyy_scripts/cloud-center-v2/cloud-center.py"
CLOUD_CENTER_REPO="${SCRIPT_DIR}/../cloudyy_scripts/cloud-center-v2/cloud-center.py"

verify_controller_bridge() {
    local file="$1"
    if grep -Fxq "WIDGETS_BRIDGE=\"${BRIDGE_SCRIPT}\"" "$file"; then
        echo "[✓] Wired quickshell bridge into $(basename "$file")"
    else
        echo "[!] Could not verify quickshell bridge in $(basename "$file") — may need manual fix" >&2
    fi
}

update_controller() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "[!] Missing theme controller target: $file — skipping" >&2
        return 0
    fi
    # Only attempt sed if the pattern line exists at all
    if ! grep -q '^WIDGETS_BRIDGE=' "$file"; then
        echo "[!] WIDGETS_BRIDGE= line not found in $(basename "$file") — skipping wire" >&2
        return 0
    fi
    sed -i "s|^WIDGETS_BRIDGE=.*|WIDGETS_BRIDGE=\"${BRIDGE_SCRIPT}\"|" "$file"
    verify_controller_bridge "$file"
}

verify_cloud_center() {
    local py_file="$1"
    if grep -Fxq 'ACTIVE_SHELL_TAB = "quickshell"' "$py_file"; then
        echo "[✓] Wired quickshell tab into $(basename "$py_file")"
    else
        echo "[!] Could not verify quickshell tab in $(basename "$py_file") — may need manual fix" >&2
    fi
}

update_cloud_center() {
    local py_file="$1"
    if [[ ! -f "$py_file" ]]; then
        echo "[!] Missing cloud-center target: $py_file — skipping" >&2
        return 0
    fi
    if ! grep -q '^ACTIVE_SHELL_TAB = ' "$py_file"; then
        echo "[!] ACTIVE_SHELL_TAB line not found in $(basename "$py_file") — skipping wire" >&2
        return 0
    fi
    sed -i 's|^ACTIVE_SHELL_TAB = ".*"|ACTIVE_SHELL_TAB = "quickshell"|' "$py_file"
    verify_cloud_center "$py_file"
}

update_controller "$THEME_CONTROLLER_HOME"
update_controller "$THEME_CONTROLLER_REPO"
update_cloud_center "$CLOUD_CENTER_HOME"
update_cloud_center "$CLOUD_CENTER_REPO"
