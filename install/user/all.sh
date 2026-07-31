#!/usr/bin/env bash
# Install per-user Cloudyy integration after configuration is deployed.
set -euo pipefail -E

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_DIR="$(cd "${INSTALL_DIR}/.." && pwd)"

usage() {
  printf 'Usage: %s [--help]\n\nInstall Cloudyy commands, desktop entries, and user services.\n' "$(basename "$0")"
}

log_warn() { printf '[!] %s\n' "$1" >&2; }

case "${1:-}" in
--help | -h) usage; exit 0 ;;
esac

local_bin="${HOME}/.local/bin"
mkdir -p "$local_bin"
for command in "${REPO_DIR}"/bin/cloudyy "${REPO_DIR}"/bin/cloudyy-*; do
  [[ -x "$command" ]] || continue
  ln -snf "$command" "${local_bin}/$(basename "$command")"
done

unit_dir="${HOME}/.config/systemd/user"
mkdir -p "$unit_dir"
install -m 0644 "${INSTALL_DIR}/assets/systemd/quickshell.service" "${unit_dir}/quickshell.service"
install -m 0644 "${INSTALL_DIR}/assets/systemd/cloudyy-unlocked.target" "${unit_dir}/cloudyy-unlocked.target"
# Lid-suspend inhibitor unit — installed but not enabled; Cloud Center's
# "Sleep when lid is closed" toggle (lib/lid_sleep_persist.py) enables it.
install -m 0644 "${INSTALL_DIR}/assets/systemd/cloudyy-lid-inhibit.service" "${unit_dir}/cloudyy-lid-inhibit.service"

bash "${SCRIPT_DIR}/desktop-entries.sh" "$REPO_DIR"
bash "${SCRIPT_DIR}/quickshell-service.sh" ||
  printf '[!] Quickshell service setup encountered issues (non-fatal).\n' >&2
audio_service_script="${SCRIPT_DIR}/audio-autoswitch.sh"
bash "$audio_service_script" \
      || log_warn "Audio auto-switch service setup encountered issues (non-fatal)."

for service in bluetooth.service NetworkManager.service power-profiles-daemon.service; do
  sudo systemctl enable --now "$service" 2>/dev/null ||
    printf '[!] Could not enable %s (non-fatal).\n' "$service" >&2
done
systemctl --user disable hyprpolkitagent.service 2>/dev/null || true
systemctl --user start hyprpolkitagent.service 2>/dev/null ||
  printf '[!] Could not start hyprpolkitagent.service (non-fatal).\n' >&2
