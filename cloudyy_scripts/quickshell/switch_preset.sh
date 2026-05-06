#!/usr/bin/env bash
# ==============================================================================
# switch_preset.sh — Switches the active Quickshell preset
# ==============================================================================
# Usage: ./switch_preset.sh <preset_name>
# ==============================================================================

set -euo pipefail

PRESET="${1:-}"
PRESET_FILE="${HOME}/.config/quickshell/.current_preset"
CONF_DIR="${HOME}/.config/quickshell"

if [[ -z "$PRESET" ]]; then
    echo "Usage: $(basename "$0") <preset_name>"
    echo "Available presets:"
    find "$CONF_DIR" -maxdepth 1 -type d ! -name ".*" ! -name "components" -exec basename {} \;
    exit 1
fi

if [[ ! -d "${CONF_DIR}/${PRESET}" ]]; then
    echo "Error: Preset '${PRESET}' not found in ${CONF_DIR}"
    exit 1
fi

echo "$PRESET" > "$PRESET_FILE"
ln -snf "${CONF_DIR}/${PRESET}/shell.qml" "${CONF_DIR}/shell.qml"
echo "[✓] Preset switched to: $PRESET (wired to root shell.qml)"

# Force a clean restart when switching presets
if command -v qs >/dev/null 2>&1; then
    qs kill >/dev/null 2>&1 || true
fi
pkill -9 -x quickshell 2>/dev/null || true
pkill -9 -x qs 2>/dev/null || true

# Trigger a reload via the bridge script
BRIDGE="${HOME}/cloudyy_scripts/bridge_scripts/bridge_quickshell.sh"
if [[ -x "$BRIDGE" ]]; then
    "$BRIDGE"
else
    # Fallback: manually restart if bridge not found
    qs kill && env QS_NO_RELOAD_POPUP=1 qs -c "$PRESET" -d
fi
