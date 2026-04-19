#!/usr/bin/env bash
# =============================================================================
# schema_settings.sh — XDG Settings Portal & pywalfox Integration Setup
# =============================================================================
# Fixes three gaps that make Firefox and pywalfox see the global dark/light
# mode set by theme_controller.sh:
#
#   1. gsettings-desktop-schemas — provides the org.gnome.desktop.interface
#      schema that theme_controller.sh writes to via gsettings.
#
#   2. xdg-desktop-portal config — routes the org.freedesktop.portal.Settings
#      interface to xdg-desktop-portal-gtk (Hyprland does not implement it).
#      Firefox reads this portal live to detect color-scheme changes.
#
#   3. pywalfox native-install — registers the native messaging host that
#      lets pywalfox communicate with the Firefox extension.
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
log()         { printf '%s[*]%s %s\n'                   "$BLUE"   "$RESET" "$1"; }
log_ok()      { printf '%s[✓]%s %s\n'                   "$GREEN"  "$RESET" "$1"; }
log_warn()    { printf '%s[!]%s %s\n'                   "$YELLOW" "$RESET" "$1"; }
log_error()   { printf '%s[✗]%s %s\n'                   "$RED"    "$RESET" "$1" >&2; }
log_skip()    { printf '%s[-]%s %s %s(skipped)%s\n'     "$CYAN"   "$RESET" "$1" "$YELLOW" "$RESET"; }
log_section() { printf '\n%s%s── %s%s\n'                "$BOLD"   "$CYAN"  "$1" "$RESET"; }

# =============================================================================
# STEP 1: gsettings-desktop-schemas
# =============================================================================

setup_gsettings_schemas() {
  log_section "gsettings-desktop-schemas"

  if pacman -Qi gsettings-desktop-schemas &>/dev/null; then
    log_skip "gsettings-desktop-schemas already installed"
    return 0
  fi

  if ! command -v pacman &>/dev/null; then
    log_error "pacman not found — install gsettings-desktop-schemas manually"
    return 1
  fi

  log "Installing gsettings-desktop-schemas..."
  if sudo pacman -S --needed --noconfirm gsettings-desktop-schemas; then
    log_ok "gsettings-desktop-schemas installed"
  else
    log_error "Failed to install gsettings-desktop-schemas"
    return 1
  fi
}

# =============================================================================
# STEP 2: xdg-desktop-portal config
# =============================================================================

setup_portal_config() {
  log_section "XDG Desktop Portal Config"

  local portal_dir="${HOME}/.config/xdg-desktop-portal"
  mkdir -p "$portal_dir"

  # --- hyprland-portals.conf ---
  # Tells xdg-desktop-portal which backends to use on Hyprland.
  # The gtk backend is listed second so it handles the Settings interface
  # (org.freedesktop.portal.Settings → color-scheme), which hyprland does not implement.
  local hyprland_conf="${portal_dir}/hyprland-portals.conf"
  if [[ -f "$hyprland_conf" ]]; then
    log_skip "hyprland-portals.conf already exists"
  else
    cat >"$hyprland_conf" <<'EOF'
[preferred]
# hyprland handles screenshots, screencasts, and file pickers.
# gtk handles org.freedesktop.portal.Settings (color-scheme) which
# hyprland does not implement — Firefox reads this portal live.
default=hyprland;gtk
EOF
    log_ok "Created hyprland-portals.conf"
  fi

  # --- portals.conf ---
  # Generic fallback config; sets a sane default color-scheme hint used before
  # gsettings has been written by theme_controller.sh for the first time.
  local portals_conf="${portal_dir}/portals.conf"
  if [[ -f "$portals_conf" ]]; then
    log_skip "portals.conf already exists"
  else
    cat >"$portals_conf" <<'EOF'
[Portal]
PreferredColorScheme=dark
EOF
    log_ok "Created portals.conf"
  fi

  log_ok "XDG portal config complete — restart xdg-desktop-portal for changes to take effect"
}

# =============================================================================
# STEP 3: pywalfox native messaging host
# =============================================================================

setup_pywalfox() {
  log_section "pywalfox Native Messaging Host"

  if ! command -v pywalfox &>/dev/null; then
    log_warn "pywalfox not found — skipping (install python-pywalfox first)"
    return 0
  fi

  # Check all known native messaging host locations for both native and Flatpak Firefox.
  local -a host_dirs=(
    "${HOME}/.mozilla/native-messaging-hosts"
    "${HOME}/.var/app/org.mozilla.firefox/.mozilla/native-messaging-hosts"
  )
  local already_installed=0
  for dir in "${host_dirs[@]}"; do
    [[ -f "${dir}/pywalfox.json" ]] && { already_installed=1; break; }
  done

  if ((already_installed)); then
    log_skip "pywalfox native messaging host already registered"
    return 0
  fi

  log "Running pywalfox native-install..."
  if pywalfox native-install; then
    log_ok "pywalfox native messaging host registered"
  else
    log_error "pywalfox native-install failed — you may need to run it manually"
    return 1
  fi
}

# =============================================================================
# STEP 4: restart xdg-desktop-portal (optional, non-fatal)
# =============================================================================

restart_portal() {
  log_section "Restarting xdg-desktop-portal"

  if ! command -v systemctl &>/dev/null; then
    log_warn "systemctl not available — restart xdg-desktop-portal manually"
    return 0
  fi

  if systemctl --user restart xdg-desktop-portal.service 2>/dev/null; then
    log_ok "xdg-desktop-portal restarted"
  else
    log_warn "Could not restart xdg-desktop-portal — a re-login will apply the new config"
  fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  printf '\n%s%s── XDG Settings Portal & pywalfox Setup ──%s\n\n' "$BOLD" "$CYAN" "$RESET"

  local errors=0

  setup_gsettings_schemas  || ((++errors))
  setup_portal_config      || ((++errors))
  setup_pywalfox           || ((++errors))
  restart_portal           || true  # non-fatal; re-login is an acceptable fallback

  printf '\n'
  if ((errors > 0)); then
    log_warn "${errors} step(s) encountered errors — see output above."
    return 1
  fi

  log_ok "All done. Firefox will now pick up dark/light mode changes from theme_controller.sh."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
