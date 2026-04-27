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
echo "[✓] Preset switched to: $PRESET"

# Trigger a reload via the bridge script (which reads the new preset)
BRIDGE="${HOME}/cloudyy_scripts/bridge_scripts/bridge_quickshell.sh"
if [[ -x "$BRIDGE" ]]; then
    "$BRIDGE"
else
    # Fallback: manually restart if bridge not found
    qs kill && qs -c "$PRESET" -d
fi
