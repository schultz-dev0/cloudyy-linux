#!/usr/bin/env bash
# =============================================================================
# setup-quickshell-service.sh — Quickshell Systemd Service Setup
# =============================================================================
# Ensures the quickshell.service user unit is active and supervised so that
# crashes (SIGSEGV in Qt/Wayland) trigger an automatic restart rather than
# leaving the shell dead until the user notices.
#
# The service file lives at:
#   ~/.config/systemd/user/quickshell.service   (deployed by deploy-dotfiles.sh)
# and is already listed in graphical-session.target.wants/ inside the repo, so
# it is enabled as soon as the dotfiles symlink is in place.
#
# This script handles the remaining first-install steps:
#   1. Reload the systemd user daemon to pick up the new unit file.
#   2. Write ~/.config/quickshell/qs.env with Cloud Center performance flags
#      (CLOUDYY_LIGHTWEIGHT) read from CC settings.
#      The service has EnvironmentFile=-%h/.config/quickshell/qs.env (optional),
#      so an empty or absent file is safe.
#   3. Start the service now if a Wayland session is already running.
#
# Safe to re-run: all steps are idempotent.
# =============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors (TTY-aware) ---
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' CYAN=$'\e[1;36m' BOLD=$'\e[1m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

# --- Logging ---
log()         { printf '%s[*]%s %s\n'               "$BLUE"   "$RESET" "$1"; }
log_ok()      { printf '%s[✓]%s %s\n'               "$GREEN"  "$RESET" "$1"; }
log_warn()    { printf '%s[!]%s %s\n'               "$YELLOW" "$RESET" "$1"; }
log_error()   { printf '%s[✗]%s %s\n'               "$RED"    "$RESET" "$1" >&2; }
log_skip()    { printf '%s[-]%s %s %s(skipped)%s\n' "$CYAN"   "$RESET" "$1" "$YELLOW" "$RESET"; }
log_section() { printf '\n%s%s── %s%s\n'            "$BOLD"   "$CYAN"  "$1" "$RESET"; }

# =============================================================================
# STEP 1: Verify service file is deployed
# =============================================================================

check_service_file() {
  log_section "Quickshell Service File"

  local unit="${HOME}/.config/systemd/user/quickshell.service"

  if [[ ! -f "$unit" ]]; then
    log_error "quickshell.service not found at ${unit}"
    log_error "Run deploy-dotfiles.sh first to symlink the dotfiles repo."
    return 1
  fi

  log_ok "quickshell.service present at ${unit}"
}

# =============================================================================
# STEP 2: Reload systemd user daemon
# =============================================================================

reload_daemon() {
  log_section "Systemd User Daemon Reload"

  if ! command -v systemctl &>/dev/null; then
    log_warn "systemctl not found — skipping daemon reload."
    return 0
  fi

  if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user disable quickshell.service 2>/dev/null || true
    log_ok "systemd user daemon reloaded"
  else
    log_warn "daemon-reload failed — systemd may not be running yet (OK during install)."
  fi
}

# =============================================================================
# STEP 3: Write qs.env
# =============================================================================
# Reads Cloud Center lightweight settings and writes the env file the service
# picks up on start. If CC settings aren't available yet (fresh install before
# CC has run), writes an empty file which is harmless.

write_env_file() {
  log_section "Quickshell Environment File"

  local env_file="${HOME}/.config/quickshell/qs.env"
  local cc_dir="${HOME}/cloudyy-linux/cloud-center"

  mkdir -p "$(dirname "$env_file")"

  # Try to read settings via the CC Python module
  if [[ -d "$cc_dir" ]] && command -v python3 &>/dev/null; then
    local env_content
    env_content="$(python3 - <<PYEOF 2>/dev/null || true
import sys
sys.path.insert(0, '${cc_dir}')
try:
    from lib.quickshell_display_settings import lightweight_enabled
    if lightweight_enabled():
        print("CLOUDYY_LIGHTWEIGHT=1")
except Exception:
    pass
PYEOF
)"
    printf '%s\n' "$env_content" > "$env_file"
    log_ok "qs.env written (from CC settings)"
  else
    # CC not available yet — write empty file; service uses the optional prefix (-)
    : > "$env_file"
    log_ok "qs.env written (empty — CC not available; rerun after first login)"
  fi
}

# =============================================================================
# STEP 4: Start the service if in a Wayland session
# =============================================================================

start_service() {
  log_section "Quickshell Service"

  if ! command -v systemctl &>/dev/null; then
    log_skip "systemctl not available"
    return 0
  fi

  if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
    log_skip "No display server detected — Cloudyy will start Quickshell after unlock"
    return 0
  fi

  if systemctl --user is-active --quiet quickshell.service 2>/dev/null; then
    log_skip "quickshell.service is already running"
    return 0
  fi

  if systemctl --user start quickshell.service 2>/dev/null; then
    log_ok "quickshell.service started"
  else
    log_warn "Could not start quickshell.service now — Cloudyy will retry after unlock."
  fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  printf '\n%s%s── Quickshell Service Setup ──%s\n\n' "$BOLD" "$CYAN" "$RESET"

  local errors=0

  check_service_file  || ((++errors))
  reload_daemon       || true   # non-fatal; OK if systemd isn't up yet during install
  write_env_file      || ((++errors))
  start_service       || true   # non-fatal; service starts on next login

  printf '\n'
  if ((errors > 0)); then
    log_warn "${errors} step(s) encountered errors — see output above."
    return 1
  fi

  log_ok "Quickshell will now auto-restart after crashes (Restart=on-failure)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
