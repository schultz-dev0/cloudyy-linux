#!/usr/bin/env bash
# =============================================================================
# cloudyy-linux — Master Installer
# =============================================================================
# Usage:
#   ./install.sh              Normal run (resumes if previous session exists)
#   ./install.sh --dry-run    Preview phases without executing anything
#   ./install.sh --reset      Clear saved state and start from the beginning
#   ./install.sh --unattended Silent install — skip post-install config prompt
#   ./install.sh --help       Show this message
# =============================================================================

set -euo pipefail -E

# --- Paths & Constants -------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="${HOME}/.local/share/cloudyy"
readonly LOG_DIR="${STATE_DIR}/logs"
readonly LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="${STATE_DIR}/.install_state"
readonly STATE_VERSION_FILE="${STATE_DIR}/.install_state_version"
readonly INSTALL_STATE_VERSION="2"
readonly LOCK_FILE="/tmp/cloudyy_install_${UID}.lock"

# --- Script-Level Variables -------------------------------------------------
UNATTENDED=0
STATE_VERSION_MISMATCH=0

# --- Colors (TTY-aware) ------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' CYAN=$'\e[1;36m' BOLD=$'\e[1m'
  RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

# --- Logging -----------------------------------------------------------------
setup_logging() {
  mkdir -p "$LOG_DIR"
  touch "$LOG_FILE"
  # Tee stdout+stderr to log file, stripping ANSI in the log copy
  exec > >(tee >(sed 's/\x1B\[[0-9;:]*[mK]//g; s/\x1B(B//g' >>"$LOG_FILE")) 2>&1
}

_ts() { date '+%H:%M:%S'; }
log() { printf '%s[>>]%s [%s] %s\n' "$BOLD" "$RESET" "$(_ts)" "$1"; }
log_ok() { printf '%s[✓]%s  [%s] %s\n' "$GREEN" "$RESET" "$(_ts)" "$1"; }
log_warn() { printf '%s[!]%s  [%s] %s\n' "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error() { printf '%s[✗]%s  [%s] %s\n' "$RED" "$RESET" "$(_ts)" "$1" >&2; }
log_phase() {
  printf '\n%s%s┌──────────────────────────────────────┐%s\n' "$BOLD" "$CYAN" "$RESET"
  printf '%s%s│  %-37s│%s\n' "$BOLD" "$CYAN" "$1" "$RESET"
  printf '%s%s└──────────────────────────────────────┘%s\n' "$BOLD" "$CYAN" "$RESET"
}

# --- State Management --------------------------------------------------------
declare -gA COMPLETED_PHASES=()

load_state() {
  unset COMPLETED_PHASES
  declare -gA COMPLETED_PHASES=()
  STATE_VERSION_MISMATCH=0

  local state_version=""
  [[ -f "$STATE_VERSION_FILE" ]] && state_version="$(<"$STATE_VERSION_FILE")"
  if [[ -s "$STATE_FILE" ]] && [[ "$state_version" != "$INSTALL_STATE_VERSION" ]]; then
    STATE_VERSION_MISMATCH=1
    log_warn "Installer layout changed — saved progress will reset when installation starts."
    return 0
  fi
  [[ -s "$STATE_FILE" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && COMPLETED_PHASES["$line"]=1
  done <"$STATE_FILE"
}

mark_done() {
  printf '%s\n' "$INSTALL_STATE_VERSION" >"$STATE_VERSION_FILE"
  echo "$1" >>"$STATE_FILE"
  COMPLETED_PHASES["$1"]=1
}

is_done() {
  [[ -n "${COMPLETED_PHASES[${1}]:-}" ]]
}

# --- Sudo Heartbeat ----------------------------------------------------------
_SUDO_PID=""

start_sudo_heartbeat() {
  log "Requesting sudo credentials..."
  if ! sudo -v; then
    log_error "Sudo authentication failed."
    exit 1
  fi
  # Keep sudo token alive in background (closes when this script exits)
  (while kill -0 "$$" 2>/dev/null; do
    sudo -n true
    sleep 50
  done) &
  _SUDO_PID=$!
}

# --- Cleanup Trap ------------------------------------------------------------
cleanup() {
  local exit_code=$?
  [[ -n "${_SUDO_PID:-}" ]] && kill "$_SUDO_PID" 2>/dev/null || true
  if [[ $exit_code -ne 0 ]]; then
    log_error "Installer exited with error code ${exit_code}."
    printf '\nYou can resume by re-running: %s./install.sh%s\n\n' "$BOLD" "$RESET"
  fi
}
trap cleanup EXIT

# =============================================================================
# PHASE FUNCTIONS
# Each phase_ function must exit 0 on success, non-zero on failure.
# =============================================================================

# --- Phase: Preflight --------------------------------------------------------
phase_preflight() {
  log "Verifying system..."

  if [[ ! -f /etc/arch-release ]]; then
    log_error "This installer targets Arch Linux only."
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/packages/manifest.sh" ]]; then
    log_error "packages/manifest.sh not found in ${SCRIPT_DIR}"
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/packages/all.sh" ]]; then
    log_error "packages/all.sh not found in ${SCRIPT_DIR}"
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/config/all.sh" ]]; then
    log_error "config/all.sh not found in ${SCRIPT_DIR}"
    return 1
  fi

  log "Checking internet connectivity..."
  if ! ping -c1 -W5 archlinux.org &>/dev/null; then
    log_error "No internet connection. Please connect and retry."
    return 1
  fi

  if ! command -v git &>/dev/null; then
    log_warn "git not found — installing it now..."
    sudo pacman -S --needed --noconfirm git
  fi

  log_ok "Preflight passed."
}

# --- Phase: Packages ---------------------------------------------------------

# --- Phase: Packages ---------------------------------------------------------
phase_packages() {
  bash "${SCRIPT_DIR}/packages/all.sh"
}

phase_other() {
  bash "${SCRIPT_DIR}/other/all.sh"
}

phase_hardware() {
  bash "${SCRIPT_DIR}/hardware/all.sh"
}

phase_config() {
  local flags=()
  [[ "${CLOUDYY_UNATTENDED:-0}" == "1" ]] && flags+=(--unattended)
  bash "${SCRIPT_DIR}/config/all.sh" "${flags[@]}"
}

phase_login_user() {
  bash "${SCRIPT_DIR}/login-user/all.sh"
}

phase_user() {
  bash "${SCRIPT_DIR}/user/all.sh"
}

phase_post_install() {
  local flags=()
  [[ "${CLOUDYY_UNATTENDED:-0}" == "1" ]] && flags+=(--unattended)
  bash "${SCRIPT_DIR}/post-install/all.sh" "${flags[@]}"
}

# --- Phase: Schema Settings --------------------------------------------------
phase_schema() {
  local schema_script="${SCRIPT_DIR}/config/schema.sh"
  if [[ ! -f "$schema_script" ]]; then
    log_warn "schema_settings.sh not found — skipping XDG portal + pywalfox setup."
    return 0
  fi
  bash "$schema_script"
  local region_time="${SCRIPT_DIR}/config/region-time.sh"
  if [[ -f "$region_time" ]]; then
    bash "$region_time"
  fi
}

# --- Phase: Laptop Support ---------------------------------------------------
phase_laptop() {
  # Skip on desktop systems (no battery detected)
  if ! ls /sys/class/power_supply/BAT* &>/dev/null; then
    log "No battery detected — skipping laptop configuration."
    return 0
  fi

  log "Laptop detected — enabling power management..."

  # Touchpad defaults are in source/input.lua (loaded by hyprland.lua on all systems).
  # No per-machine config injection needed.

  # Enable power-profiles-daemon if available
  if command -v powerprofilesctl &>/dev/null; then
    if sudo systemctl enable --now power-profiles-daemon.service 2>/dev/null; then
      log_ok "power-profiles-daemon enabled."
    else
      log_warn "Could not enable power-profiles-daemon (non-fatal)."
    fi
  fi

  log_ok "Laptop configuration complete."
}

phase_services() {
  log "Enabling system services..."

  local -a services=(
    "bluetooth.service"
    "NetworkManager.service"
    "power-profiles-daemon.service"
    "geoclue.service"
  )

  for svc in "${services[@]}"; do
    if sudo systemctl enable --now "$svc" 2>/dev/null; then
      log_ok "Enabled: ${svc}"
    else
      log_warn "Could not enable ${svc} — it may not be installed yet."
    fi
  done

  if systemctl --user enable --now hyprpolkitagent.service 2>/dev/null; then
    log_ok "Enabled: hyprpolkitagent.service (user)"
  else
    log_warn "Could not enable hyprpolkitagent.service — polkit password dialogs may not appear."
  fi

  local qs_service_script="${SCRIPT_DIR}/user/quickshell-service.sh"
  if [[ -f "$qs_service_script" ]]; then
    bash "$qs_service_script" || log_warn "Quickshell service setup encountered issues (non-fatal)."
  else
    log_warn "setup-quickshell-service.sh not found — quickshell crash-restart will not be configured."
  fi

  local audio_service_script="${SCRIPT_DIR}/user/audio-autoswitch.sh"
  if [[ -f "$audio_service_script" ]]; then
    bash "$audio_service_script" ||
      log_warn "Audio auto-switch service setup encountered issues (non-fatal)."
  else
    log_warn "Audio auto-switch setup script not found."
  fi

  log_ok "Services configured."
}

# --- Phase: Theme Bootstrap --------------------------------------------------
# Runs after packages so matugen is available to generate hyprcolors.conf.
phase_theme_init() {
  local state_conf="${HOME}/.config/hypr/theme_state/state.conf"
  local default_wall="${HOME}/Wallpapers/Dark/cloudyy.jpg"
  local current_wall="${HOME}/.config/hypr/theme_state/current_wallpaper/current.jpg"

  if ! command -v cloudyy-theme >/dev/null 2>&1; then
    log_warn "cloudyy-theme not found on PATH — skipping theme bootstrap."
    return 0
  fi

  # Seed state.conf with the default wallpaper so restore has something to run matugen against.
  # Only seeds if no wallpaper is already saved.
  if [[ -f "$state_conf" ]] && grep -q 'CURRENT_WALL="[^"]' "$state_conf" 2>/dev/null; then
    log "Existing theme state found — preserving."
  elif [[ -f "$default_wall" ]]; then
    mkdir -p "$(dirname "$state_conf")"
    printf 'THEME_MODE="dark"\nCURRENT_WALL="%s"\n' "$default_wall" >"$state_conf"
    log "Default wallpaper seeded into theme state."
  fi

  # The lockscreen reads this snapshot directly, including before the wallpaper
  # daemon or theme controller has had a chance to run on first login.
  if [[ ! -f "$current_wall" && -f "$default_wall" ]]; then
    mkdir -p "$(dirname "$current_wall")"
    cp "$default_wall" "$current_wall"
    log "Default wallpaper seeded into lockscreen snapshot."
  fi

  if cloudyy-theme restore >/dev/null 2>&1; then
    log_ok "Theme colours generated."
  else
    log_warn "Theme bootstrap failed (non-fatal — run 'cloudyy-theme restore' later)."
  fi

  # Generate thumbs during install time instead of on first request on first boot. Reuse thumb_cache.sh
  local repo_root="$(dirname "${SCRIPT_DIR}")"
  local thumb_lib="${repo_root}/lib/thumb_cache.sh"
  if [[ -f "$thumb_lib" ]] && { command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; }; then
    local CACHE_DIR="${HOME}/.cache/rofi_thumbs" THUMB_SIZE=256
    mkdir -p "$CACHE_DIR"
    # shellcheck source=../lib/thumb_cache.sh
    source "$thumb_lib"
    export -f gen_thumb canonical_real find_cached_thumb promote_thumb thumb_file_for_path path_aliases path_hash
    export CACHE_DIR THUMB_SIZE HOME
    find -L "${HOME}/Wallpapers/Dark" "${HOME}/Wallpapers/Light" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
      -print0 2>/dev/null | xargs -0 -P "$(nproc 2>/dev/null || echo 4)" -I {} bash -c 'gen_thumb "$1" >/dev/null' _ {}
    log_ok "Wallpaper thumbnails pre-generated."
  else
    log_warn "imagemagick not found — skipping thumbnail pre-generation (picker will generate on first use)."
  fi
}

# --- Phase: Boot Setup -------------------------------------------------------
# Configures autologin, bootloader timeout, system-wide zprofile Hyprland
# autostart, and rebuilds initramfs. Requires sudo; runs after packages so
# uwsm is available.
phase_boot_setup() {
  if ! command -v cloudyy-boot-opt >/dev/null 2>&1; then
    log_warn "cloudyy-boot-opt not found on PATH — skipping boot optimisation."
    return 0
  fi
  sudo cloudyy-boot-opt "$USER"
}

# --- Phase: Finalize ---------------------------------------------------------
phase_finalize() {
  printf '\n%s%s════════════════════════════════════════════%s\n' "$BOLD" "$GREEN" "$RESET"
  printf '%s  🎉  cloudyy-linux installation complete!  %s\n' "$BOLD" "$RESET"
  printf '%s%s════════════════════════════════════════════%s\n\n' "$BOLD" "$GREEN" "$RESET"
  printf 'Log saved to:\n  %s%s%s\n\n' "$CYAN" "$LOG_FILE" "$RESET"

  if [[ "${UNATTENDED}" != "1" ]] && command -v cloudyy-config >/dev/null 2>&1; then
    cloudyy-config --first-run
  fi

  printf '%sNext steps:%s\n' "$YELLOW" "$RESET"
  printf '  1. Log out of your current session\n'
  printf '  2. Select Hyprland at your display manager, or run: %sHyprland%s\n' "$BOLD" "$RESET"
  printf '  3. Run %s./install.sh --reset%s if you ever want to reinstall from scratch\n\n' "$BOLD" "$RESET"
}

# =============================================================================
# PHASE REGISTRY (ordered)
# =============================================================================
declare -a PHASE_IDS=(
  "preflight"
  "packages"
  "hardware"
  "config"
  "login_user"
  "user"
  "other"
  "post_install"
  "finalize"
)

declare -A PHASE_LABELS=(
  [preflight]="System Preflight Checks"
  [packages]="Package Installation"
  [hardware]="Hardware Configuration"
  [config]="Configuration Deployment"
  [login_user]="Login & User Setup"
  [user]="User Commands & Services"
  [other]="Other Setup"
  [post_install]="Post-install Configuration"
  [finalize]="Finalization"
)

# =============================================================================
# MAIN
# =============================================================================
main() {
  # --- Argument Handling ---
  case "${1:-}" in
  --help | -h)
    printf 'Usage: %s [--dry-run | --reset | --unattended | --help]\n' "$(basename "$0")"
    printf '\n  --dry-run      Preview phases without making changes\n'
    printf '  --reset        Clear saved progress and start from scratch\n'
    printf '  --unattended   Silent install — skip post-install config prompt\n\n'
    exit 0
    ;;
  --reset)
    rm -f "$STATE_FILE" "$STATE_VERSION_FILE"
    printf '%sState cleared.%s Re-run without --reset to start fresh.\n' "$GREEN" "$RESET"
    exit 0
    ;;
  --dry-run | -d)
    load_state 2>/dev/null || true
    printf '\n%s=== DRY RUN — nothing will be executed ===%s\n\n' "$YELLOW" "$RESET"
    local i=1
    for id in "${PHASE_IDS[@]}"; do
      local status
      is_done "$id" &&
        status="${GREEN}[DONE]${RESET}" ||
        status="${BLUE}[PENDING]${RESET}"
      printf '  %d. %-38s %b\n' "$i" "${PHASE_LABELS[$id]}" "$status"
      ((i++))
    done
    printf '\n'
    exit 0
    ;;
  --unattended | -u)
    UNATTENDED=1
    export CLOUDYY_UNATTENDED=1
    ;;
  "") ;;
  *)
    printf '%sUnknown option: %s%s\n' "$RED" "$1" "$RESET" >&2
    printf 'Run %s --help for usage.\n' "$(basename "$0")" >&2
    exit 1
    ;;
  esac

  # --- Root Guard ---
  if [[ $EUID -eq 0 ]]; then
    log_error "Do not run as root. This script manages sudo internally."
    exit 1
  fi

  _err_handler() {
    log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
    log_error "  in ${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}:${FUNCNAME[1]:-main}"
  }
  trap '_err_handler' ERR

  # --- Concurrent Execution Guard ---
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log_error "Another cloudyy install session is already running."
    exit 1
  fi

  # --- Setup ---
  mkdir -p "$STATE_DIR"
  setup_logging

  # --- Banner ---
  clear
  printf '%s' "$CYAN"
  cat <<'BANNER'
  ╔══════════════════════════════════════════════════════════╗
  ║                                                          ║
  ║          cloudyy-linux  —  Hyprland Installer           ║
  ║          Arch Linux  ·  Wayland  ·  Hyprland            ║
  ║                                                          ║
  ╚══════════════════════════════════════════════════════════╝
BANNER
  printf '%s\n' "$RESET"

  # --- Session Recovery ---
  load_state
  local completed_count=0
  for id in "${PHASE_IDS[@]}"; do
    is_done "$id" && ((++completed_count)) || true
  done
  local total_phases=${#PHASE_IDS[@]}

  if ((completed_count > 0 && completed_count < total_phases)); then
    printf '%s>>> Previous session detected (%d/%d phases complete)%s\n' \
      "$YELLOW" "$completed_count" "$total_phases" "$RESET"
    if [[ "${CLOUDYY_UNATTENDED:-0}" == "1" ]]; then
      log "Unattended mode — resuming from last checkpoint."
    else
      read -rp "    [C]ontinue where you left off, or [S]tart over? [C/s]: " _session_choice
      if [[ "${_session_choice,,}" == "s" ]]; then
        rm -f "$STATE_FILE"
        load_state
        log_ok "Starting fresh."
      else
        log_ok "Resuming from last checkpoint."
      fi
    fi
  fi

  # --- Execution Plan Preview ---
  printf '\n%sInstallation plan:%s\n' "$BOLD" "$RESET"
  local i=1
  for id in "${PHASE_IDS[@]}"; do
    if is_done "$id"; then
      printf '  %s✓%s  %d. %s %s(already done)%s\n' \
        "$GREEN" "$RESET" "$i" "${PHASE_LABELS[$id]}" "$YELLOW" "$RESET"
    else
      printf '  %s•%s  %d. %s\n' "$CYAN" "$RESET" "$i" "${PHASE_LABELS[$id]}"
    fi
    ((i++))
  done
  printf '\n'
  printf '%sThis may take 10–30 minutes depending on your internet speed.%s\n' "$YELLOW" "$RESET"
  printf '\n'
  if [[ "${CLOUDYY_UNATTENDED:-0}" != "1" ]]; then
    read -rp "Proceed? [Y/n]: " _confirm
    [[ "${_confirm,,}" == "n" ]] && {
      log "Cancelled by user."
      exit 0
    }
  else
    log "Unattended mode — proceeding automatically."
  fi

  # --- Acquire Sudo ---
  if ((STATE_VERSION_MISMATCH)); then
    rm -f "$STATE_FILE" "$STATE_VERSION_FILE"
    log_warn "Previous installer progress reset for the new layout."
  fi
  touch "$STATE_FILE"
  export CLOUDYY_INSTALL_ORCHESTRATED=1
  start_sudo_heartbeat

  # --- Execute Phases ---
  local start_ts=$SECONDS

  for id in "${PHASE_IDS[@]}"; do
    if is_done "$id"; then
      log_warn "Skipping ${PHASE_LABELS[$id]} — already completed."
      continue
    fi

    log_phase "${PHASE_LABELS[$id]}"

    local phase_rc=0
    local _phase_start=$SECONDS
    "phase_${id}" || phase_rc=$?
    local _phase_elapsed=$((SECONDS - _phase_start))

    if ((phase_rc == 0)); then
      mark_done "$id"
      log_ok "${PHASE_LABELS[$id]} — complete. (${_phase_elapsed}s)"
    else
      log_error "${PHASE_LABELS[$id]} failed (exit code: ${phase_rc})."
      if [[ "${CLOUDYY_UNATTENDED:-0}" == "1" ]]; then
        log_warn "Unattended mode — skipping failed phase: ${PHASE_LABELS[$id]}"
      else
        printf '\n%sWhat would you like to do?%s\n' "$YELLOW" "$RESET"
        printf '  [R] Retry this phase\n'
        printf '  [S] Skip and continue\n'
        printf '  [Q] Quit (progress is saved — re-run to resume)\n\n'
        read -rp "Choice [r/s/Q]: " _fail_choice

        case "${_fail_choice,,}" in
        r)
          log "Retrying ${PHASE_LABELS[$id]}..."
          if "phase_${id}"; then
            mark_done "$id"
            log_ok "${PHASE_LABELS[$id]} — complete on retry."
          else
            log_error "Retry also failed."
            log_warn "Skipping ${PHASE_LABELS[$id]} — you can re-run later."
          fi
          ;;
        s)
          log_warn "Skipping ${PHASE_LABELS[$id]} by user request."
          ;;
        *)
          log "Exiting. Run ./install.sh to resume from this phase."
          exit 1
          ;;
        esac
      fi
    fi
  done

  # --- Summary ---
  local elapsed=$((SECONDS - start_ts))
  printf '\nTotal time: %dm %ds\n' "$((elapsed / 60))" "$((elapsed % 60))"
}

main "$@"
