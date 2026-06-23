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
_ts() { date '+%H:%M:%S'; }
log()         { printf '%s[*]%s  [%s] %s\n'    "$BLUE"   "$RESET" "$(_ts)" "$1"; }
log_ok()      { printf '%s[✓]%s  [%s] %s\n'   "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_warn()    { printf '%s[!]%s  [%s] %s\n'   "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error()   { printf '%s[✗]%s  [%s] %s\n'   "$RED"    "$RESET" "$(_ts)" "$1" >&2; }
log_skip()    { printf '%s[-]%s  [%s] %s\n'   "$DIM"    "$RESET" "$(_ts)" "$1"; }
log_section() { printf '\n%s%s── %s%s\n'       "$BOLD"   "$CYAN"  "$1"     "$RESET"; }
divider()     { printf '%s─────────────────────────────────────────────%s\n' "$DIM" "$RESET"; }
log_cmd()     { printf '%s[cmd]%s [%s] %s\n'  "$DIM"    "$RESET" "$(_ts)" "$*"; "$@"; }

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
    if sudo pacman -S --needed --noconfirm "$pkg" >/dev/null; then
      log_ok "  ✓ ${pkg}"
    else
      log_warn "  ✗ ${pkg}"
      fails=$(( fails + 1 ))
    fi
  done
  if (( fails > 0 )); then log_warn "${group}: ${fails} package(s) skipped."; fi
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
    if "$AUR_HELPER" -S --needed --noconfirm "$pkg" >/dev/null; then
      log_ok "  ✓ ${pkg}"
    else
      log_warn "  ✗ ${pkg}"
      fails=$(( fails + 1 ))
    fi
  done
  if (( fails > 0 )); then log_warn "${group}: ${fails} package(s) skipped."; fi
  return 0
}

# AUR installs to /usr/bin; Quickshell and shell PATH use ~/.local/bin (symlinked after install).
link_aur_binary_to_local_bin() {
  local name="$1"
  local aur_pkg="${2:-}"
  local aur_bin="/usr/bin/${name}"
  local local_bin="${HOME}/.local/bin/${name}"

  if [[ ! -x "$aur_bin" ]]; then
    log_error "${name} missing from AUR install: ${aur_bin}"
    [[ -n "$aur_pkg" ]] && log_error "Expected after: ${AUR_HELPER:-yay} -S ${aur_pkg}"
    return 1
  fi

  mkdir -p "${HOME}/.local/bin"
  ln -snf "$aur_bin" "$local_bin"
  log_ok "Linked ${local_bin} → ${aur_bin}"
}

verify_local_binary() {
  local name="$1"
  shift
  local bin="${HOME}/.local/bin/${name}"

  if [[ ! -x "$bin" ]]; then
    log_error "${name} missing: ${bin}"
    return 1
  fi

  if ! "$@" >/dev/null 2>&1; then
    log_error "${name} failed smoke test: $*"
    return 1
  fi

  log_ok "${name} verified at ${bin}"
}

readonly CLOUDYY_SYSTEM_MONITOR_AUR_PKG="cloudyy-system-monitor-git"
readonly CLOUDYY_SYSTEM_MONITOR_BIN="${HOME}/.local/bin/cloudyy-system-monitor"

deploy_system_monitor() {
  link_aur_binary_to_local_bin "cloudyy-system-monitor" "$CLOUDYY_SYSTEM_MONITOR_AUR_PKG"
}

verify_system_monitor() {
  verify_local_binary "cloudyy-system-monitor" cloudyy-system-monitor --once
}

readonly HCM_AUR_PKG="cloudyy-hcm-git"
readonly HCM_BIN="${HOME}/.local/bin/hcm"

deploy_hcm() {
  link_aur_binary_to_local_bin "hcm" "$HCM_AUR_PKG"
}

verify_hcm() {
  verify_local_binary "hcm" hcm --version
}
