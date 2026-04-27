#!/usr/bin/env bash
# =============================================================================
# cloudyy-linux — Master Installer
# =============================================================================
# Usage:
#   ./install.sh              Normal run (resumes if previous session exists)
#   ./install.sh --dry-run    Preview phases without executing anything
#   ./install.sh --reset      Clear saved state and start from the beginning
#   ./install.sh --help       Show this message
# =============================================================================

set -euo pipefail

# --- Paths & Constants -------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="${HOME}/.local/share/cloudyy"
readonly LOG_DIR="${STATE_DIR}/logs"
readonly LOG_FILE="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
readonly STATE_FILE="${STATE_DIR}/.install_state"
readonly LOCK_FILE="/tmp/cloudyy_install_${UID}.lock"

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

log() { printf '%s[>>]%s %s\n' "$BOLD" "$RESET" "$1"; }
log_ok() { printf '%s[✓]%s  %s\n' "$GREEN" "$RESET" "$1"; }
log_warn() { printf '%s[!]%s  %s\n' "$YELLOW" "$RESET" "$1"; }
log_error() { printf '%s[✗]%s  %s\n' "$RED" "$RESET" "$1" >&2; }
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
  [[ -s "$STATE_FILE" ]] || return 0
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && COMPLETED_PHASES["$line"]=1
  done <"$STATE_FILE"
}

mark_done() {
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

  if [[ ! -f "${SCRIPT_DIR}/dependencies.conf" ]]; then
    log_error "dependencies.conf not found in ${SCRIPT_DIR}"
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/hyprland-install.sh" ]]; then
    log_error "hyprland-install.sh not found in ${SCRIPT_DIR}"
    return 1
  fi

  if [[ ! -f "${SCRIPT_DIR}/deploy-dotfiles.sh" ]]; then
    log_error "deploy-dotfiles.sh not found in ${SCRIPT_DIR}"
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

# --- Phase: Shell Stack ------------------------------------------------------
# Lets the user pick which user-facing shell components to install (default
# waybar/swaync stack vs. quickshell, plus reserved slots for future swaps).
# Selection is persisted to ${STATE_DIR}/shell-stack and consumed by:
#   • hyprland-install.sh  (extra package list)
#   • apply-shell-stack.sh (writes ~/.config/hypr/source/shell-stack.conf)
phase_shell_stack() {
  STATE_DIR="$STATE_DIR" bash "${SCRIPT_DIR}/select-shell-stack.sh"
}

# --- Phase: Packages ---------------------------------------------------------
phase_packages() {
  # Export the chosen profile so hyprland-install.sh picks up its packages.
  if [[ -f "${STATE_DIR}/shell-stack" ]]; then
    export CLOUDYY_SHELL_STACK="$(<"${STATE_DIR}/shell-stack")"
  fi
  bash "${SCRIPT_DIR}/hyprland-install.sh"
}

# --- Phase: Dotfiles ---------------------------------------------------------
phase_dotfiles() {
  bash "${SCRIPT_DIR}/deploy-dotfiles.sh"
}

# --- Phase: Services ---------------------------------------------------------
phase_services() {
  log "Enabling system services..."

  local -a services=(
    "bluetooth.service"
    "NetworkManager.service"
  )

  for svc in "${services[@]}"; do
    if sudo systemctl enable --now "$svc" 2>/dev/null; then
      log_ok "Enabled: ${svc}"
    else
      log_warn "Could not enable ${svc} — it may not be installed yet."
    fi
  done

  log_ok "Services configured."
}

# --- Phase: Finalize ---------------------------------------------------------
phase_finalize() {
  printf '\n%s%s════════════════════════════════════════════%s\n' "$BOLD" "$GREEN" "$RESET"
  printf '%s  🎉  cloudyy-linux installation complete!  %s\n' "$BOLD" "$RESET"
  printf '%s%s════════════════════════════════════════════%s\n\n' "$BOLD" "$GREEN" "$RESET"
  printf 'Log saved to:\n  %s%s%s\n\n' "$CYAN" "$LOG_FILE" "$RESET"
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
  "shell_stack"
  "dotfiles"
  "packages"
  "services"
  "finalize"
)

declare -A PHASE_LABELS=(
  [preflight]="System Preflight Checks"
  [shell_stack]="Shell Stack Selection"
  [dotfiles]="Dotfiles Deployment"
  [packages]="Hardware & Package Installation"
  [services]="Service Configuration"
  [finalize]="Finalization"
)

# =============================================================================
# MAIN
# =============================================================================
main() {
  # --- Argument Handling ---
  case "${1:-}" in
  --help | -h)
    printf 'Usage: %s [--dry-run | --reset | --help]\n' "$(basename "$0")"
    printf '\n  --dry-run   Preview phases without making changes\n'
    printf '  --reset     Clear saved progress and start from scratch\n\n'
    exit 0
    ;;
  --reset)
    rm -f "$STATE_FILE"
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
    read -rp "    [C]ontinue where you left off, or [S]tart over? [C/s]: " _session_choice
    if [[ "${_session_choice,,}" == "s" ]]; then
      rm -f "$STATE_FILE"
      load_state
      log_ok "Starting fresh."
    else
      log_ok "Resuming from last checkpoint."
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
  read -rp "Proceed? [Y/n]: " _confirm
  [[ "${_confirm,,}" == "n" ]] && {
    log "Cancelled by user."
    exit 0
  }

  # --- Acquire Sudo ---
  touch "$STATE_FILE"
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
    "phase_${id}" || phase_rc=$?

    if ((phase_rc == 0)); then
      mark_done "$id"
      log_ok "${PHASE_LABELS[$id]} — complete."
    else
      log_error "${PHASE_LABELS[$id]} failed (exit code: ${phase_rc})."
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
  done

  # --- Summary ---
  local elapsed=$((SECONDS - start_ts))
  printf '\nTotal time: %dm %ds\n' "$((elapsed / 60))" "$((elapsed % 60))"
}

main "$@"
