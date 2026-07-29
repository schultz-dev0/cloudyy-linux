#!/usr/bin/env bash
# Apply hardware-specific configuration after packages are installed.
set -euo pipefail -E

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  printf 'Usage: %s [--help]\n\nConfigure detected laptop power support. GPU drivers are handled by packages/all.sh.\n' "$(basename "$0")"
}

case "${1:-}" in
--help | -h) usage; exit 0 ;;
esac

# The package installer exports the GPU detector without running main when it
# is sourced. Hardware owns invoking it as a distinct, rerunnable stage.
# shellcheck source=install/packages/install.sh
source "${SCRIPT_DIR}/../packages/install.sh"
detect_and_install_gpu

if ! ls /sys/class/power_supply/BAT* &>/dev/null; then
  printf '[*] No battery detected — skipping laptop configuration.\n'
  exit 0
fi

if command -v powerprofilesctl &>/dev/null; then
  sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null ||
    printf '[!] Could not enable power-profiles-daemon (non-fatal).\n' >&2
fi

printf '[✓] Laptop configuration complete.\n'
