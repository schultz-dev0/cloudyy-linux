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
QS_RELOAD="${HOME}/cloudyy_scripts/quickshell_reload.sh"

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

if [[ -x "$QS_RELOAD" ]]; then
    exec "$QS_RELOAD"
fi

echo "Error: quickshell_reload.sh not found or not executable: $QS_RELOAD" >&2
exit 1
