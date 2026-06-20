#!/usr/bin/env bash
# setup-keyring.sh — Automates GNOME Keyring unlocking for hyprlock

set -euo pipefail -E

# --- Colors ------------------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' DIM=$'\e[2m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' DIM='' RESET=''
fi

_ts() { date '+%H:%M:%S'; }
log()       { printf '%s[*]%s  [%s] %s\n' "$BLUE"   "$RESET" "$(_ts)" "$1"; }
log_ok()    { printf '%s[✓]%s  [%s] %s\n' "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_warn()  { printf '%s[!]%s  [%s] %s\n' "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error() { printf '%s[✗]%s  [%s] %s\n' "$RED"    "$RESET" "$(_ts)" "$1" >&2; }

_err_handler() {
  log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  log_error "  in ${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}:${FUNCNAME[1]:-main}"
}
trap '_err_handler' ERR

# ── Sync Keyring password with User password ─────────────────────────────────
log "Configuring PAM to sync Keyring password with system password..."

if ! grep -q "pam_gnome_keyring.so" /etc/pam.d/passwd 2>/dev/null; then
  echo "password        optional        pam_gnome_keyring.so" | sudo tee -a /etc/pam.d/passwd > /dev/null
  log_ok "Password sync configured in /etc/pam.d/passwd."
else
  log_ok "Password sync already configured."
fi
