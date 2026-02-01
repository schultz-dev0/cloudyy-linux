#!/usr/bin/env bash
# ==============================================================================
# REBOOT TO WINDOWS (UEFI/Limine Safe Mode)
# ==============================================================================

set -euo pipefail

# --- CHECKS ---

# 1. Check for Root
if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

# 2. Check for efibootmgr
if ! command -v efibootmgr >/dev/null 2>&1; then
  echo "Error: 'efibootmgr' is required."
  echo "Install it with: sudo pacman -S efibootmgr"
  exit 1
fi

# --- LOGIC ---

echo ">> Searching for Windows Boot Manager..."

# Find the Boot ID for Windows (e.g., "0001")
# We grep for 'Windows Boot Manager', grab the first column (BootXXXX*),
# and strip 'Boot' and the '*' to get just the hex code.
WINDOWS_ID=$(efibootmgr | grep -i "Windows Boot Manager" | head -n1 | awk '{print $1}' | sed 's/Boot//;s/\*//')

if [[ -z "$WINDOWS_ID" ]]; then
  echo "Error: Could not find 'Windows Boot Manager' in UEFI entries."
  echo "Current entries:"
  efibootmgr
  exit 1
fi

echo ">> Found Windows at Boot ID: $WINDOWS_ID"
echo ">> Setting EFI BootNext..."

# Set the "BootNext" variable
efibootmgr --bootnext "$WINDOWS_ID"

echo ">> Success. Rebooting into Windows now..."
sleep 2
reboot
