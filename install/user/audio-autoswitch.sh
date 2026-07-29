#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
readonly UNIT_NAME="cloudyy-audio-autoswitch.service"
readonly UNIT_PATH="${HOME}/.config/systemd/user/${UNIT_NAME}"
readonly CONFIG_PATH="${HOME}/.config/cloud-center/auto_switch.json"

# shellcheck source=install/other/lib.sh
source "${INSTALL_DIR}/other/lib.sh"

[[ -f "$UNIT_PATH" ]] || {
  log_warn "${UNIT_NAME} is not deployed; rerun dotfile deployment first."
  exit 0
}

command -v systemctl >/dev/null 2>&1 || {
  log_warn "systemctl unavailable; skipping Audio service setup."
  exit 0
}

systemctl --user daemon-reload 2>/dev/null || {
  log_warn "User systemd unavailable; Audio service will be offered from Cloud Center."
  exit 0
}

desired="$(python3 - "$CONFIG_PATH" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
config = {"bluetooth_auto_switch": True, "enabled": False}
if path.is_file():
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, dict):
            config.update(value)
    except (OSError, json.JSONDecodeError):
        pass
print("1" if config.get("bluetooth_auto_switch", True) or config.get("enabled", False) else "0")
PY
)"

if [[ "$desired" == "1" ]]; then
  systemctl --user enable --now "$UNIT_NAME" 2>/dev/null \
    && log_ok "Audio auto-switch service enabled" \
    || log_warn "Could not enable ${UNIT_NAME}; Cloud Center will offer to retry."
else
  systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
  log_ok "Audio auto-switch service disabled by saved preference"
fi
