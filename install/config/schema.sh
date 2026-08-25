#!/usr/bin/env bash
# =============================================================================
# schema_settings.sh — XDG Settings Portal Integration Setup
# =============================================================================
# Configures the schema and portal paths that let applications observe the
# active curated theme's declared system color-scheme preference:
#
#   1. gsettings-desktop-schemas — provides the org.gnome.desktop.interface
#      schema that cloudyy-theme writes to via gsettings.
#
#   2. xdg-desktop-portal config — routes the org.freedesktop.portal.Settings
#      interface to xdg-desktop-portal-gtk (Hyprland does not implement it).
#      Firefox reads this portal live to detect color-scheme changes.
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
  # cloudyy-theme has reconciled the active package for the first time.
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
# STEP 3: system font
# =============================================================================

setup_system_font() {
  log_section "System Font"

  local current
  current=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null || true)

  if [[ "$current" == *"JetBrainsMono Nerd Font"* ]]; then
    log_skip "font-name already set to JetBrainsMono Nerd Font"
    return 0
  fi

  gsettings set org.gnome.desktop.interface font-name 'JetBrainsMono Nerd Font 11'
  log_ok "Set org.gnome.desktop.interface font-name → JetBrainsMono Nerd Font 11"
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
# STEP 5: Thunar full path in window title (for cwd_walk.sh)
# =============================================================================

setup_thunar_full_path_title() {
  log_section "Thunar Full Path Window Title"

  if ! command -v xfconf-query &>/dev/null; then
    log_skip "xfconf-query not found — set Thunar title style manually for cwd_walk"
    return 0
  fi

  local style="THUNAR_WINDOW_TITLE_STYLE_FULL_PATH_WITHOUT_THUNAR_SUFFIX"
  local current=""
  current=$(xfconf-query -c thunar -p /misc-window-title-style 2>/dev/null || true)

  if [[ "$current" == "$style" \
     || "$current" == "THUNAR_WINDOW_TITLE_STYLE_FULL_PATH_WITH_THUNAR_SUFFIX" ]]; then
    log_skip "Thunar window title already shows full path"
    return 0
  fi

  if xfconf-query --channel thunar \
      --property /misc-window-title-style \
      --create --type string \
      --set "$style"; then
    log_ok "Set Thunar misc-window-title-style to full path"
    log "Restart Thunar (thunar -q) for cwd_walk to read folder paths from the title"
  else
    log_error "Failed to set Thunar window title style"
    return 1
  fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  printf '\n%s%s── XDG Settings Portal Setup ──%s\n\n' "$BOLD" "$CYAN" "$RESET"

  local errors=0

  setup_gsettings_schemas       || ((++errors))
  setup_portal_config           || ((++errors))
  setup_system_font             || ((++errors))
  setup_thunar_full_path_title  || ((++errors))
  restart_portal                || true  # non-fatal; re-login is an acceptable fallback

  printf '\n'
  if ((errors > 0)); then
    log_warn "${errors} step(s) encountered errors — see output above."
    return 1
  fi

  log_ok "All done. Applications can now observe the active theme's declared color scheme."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
