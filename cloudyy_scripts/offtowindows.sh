#!/usr/bin/env bash
# ==============================================================================
# SAFE SWITCH TO WINDOWS (MSI Z690 FIX)
# ==============================================================================

set -euo pipefail

# Your Windows ID (Double check this with: awk -F"'" '/menuentry / {print $2}' /boot/grub/grub.cfg)
readonly WINDOWS_ENTRY="Windows Boot Manager (on /dev/nvme0n1p1)"

if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

# 1. Tell GRUB to boot Windows *next time only*
if grep -Fq "$WINDOWS_ENTRY" /boot/grub/grub.cfg; then
  grub-reboot "$WINDOWS_ENTRY"
  echo ">> Target set: Windows"
else
  echo "Error: Windows entry not found!"
  exit 1
fi

# 2. FULL POWER CUT (Required for MSI Z690 USB Controller reset)
echo ">> SHUTTING DOWN to clear USB controller state..."
echo ">> Wait 5 seconds after lights out, then power on manually."
sleep 2
poweroff
