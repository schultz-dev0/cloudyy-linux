#!/usr/bin/env bash
# =============================================================================
# lib.sh — Shared utilities for cloudyy-linux install scripts
# Source this file; do not execute directly.
# =============================================================================
[[ -n "${_CLOUDYY_LIB_LOADED:-}" ]] && return 0
_CLOUDYY_LIB_LOADED=1

# --- Colors (TTY-aware) -------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' CYAN=$'\e[1;36m' BOLD=$'\e[1m'
  DIM=$'\e[2m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

# --- Logging ------------------------------------------------------------------
log()         { printf '%s[*]%s %s\n'    "$BLUE"   "$RESET" "$1"; }
log_ok()      { printf '%s[✓]%s %s\n'   "$GREEN"  "$RESET" "$1"; }
log_warn()    { printf '%s[!]%s %s\n'   "$YELLOW" "$RESET" "$1"; }
log_error()   { printf '%s[✗]%s %s\n'   "$RED"    "$RESET" "$1" >&2; }
log_skip()    { printf '%s[-]%s %s\n'   "$DIM"    "$RESET" "$1"; }
log_section() { printf '\n%s%s── %s%s\n' "$BOLD"  "$CYAN"  "$1" "$RESET"; }
divider()     { printf '%s─────────────────────────────────────────────%s\n' "$DIM" "$RESET"; }

# --- AUR Helper (set by setup_aur_helper in hyprland-install.sh) -------------
AUR_HELPER=""

# --- Package Installation -----------------------------------------------------
pacman_install() {
  local group="$1"; shift
  local -a pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  log "pacman [${group}] — ${#pkgs[@]} pkg(s)"
  if sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
    log_ok "${group}"
    return 0
  fi
  log_warn "${group} — batch failed, retrying individually..."
  local fails=0
  for pkg in "${pkgs[@]}"; do
    if sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
      log_ok "  ✓ ${pkg}"
    else
      log_warn "  ✗ ${pkg}"
      fails=$(( fails + 1 ))
    fi
  done
  (( fails > 0 )) && log_warn "${group}: ${fails} package(s) skipped." || true
  return 0
}

aur_install() {
  local group="$1"; shift
  local -a pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  if [[ -z "$AUR_HELPER" ]]; then
    log_warn "No AUR helper — skipping [${group}]"
    return 0
  fi
  log "${AUR_HELPER} [${group}] — ${#pkgs[@]} pkg(s)"
  if "$AUR_HELPER" -S --needed --noconfirm "${pkgs[@]}"; then
    log_ok "${group}"
    return 0
  fi
  log_warn "${group} — batch failed, retrying individually..."
  local fails=0
  for pkg in "${pkgs[@]}"; do
    if "$AUR_HELPER" -S --needed --noconfirm "$pkg" &>/dev/null; then
      log_ok "  ✓ ${pkg}"
    else
      log_warn "  ✗ ${pkg}"
      fails=$(( fails + 1 ))
    fi
  done
  (( fails > 0 )) && log_warn "${group}: ${fails} package(s) skipped." || true
  return 0
}
