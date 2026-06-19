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
readonly LOCK_FILE="/tmp/cloudyy_install_${UID}.lock"

# --- Script-Level Variables -------------------------------------------------
UNATTENDED=0

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
log()       { printf '%s[>>]%s [%s] %s\n' "$BOLD"   "$RESET" "$(_ts)" "$1"; }
log_ok()    { printf '%s[✓]%s  [%s] %s\n' "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_warn()  { printf '%s[!]%s  [%s] %s\n' "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error() { printf '%s[✗]%s  [%s] %s\n' "$RED"    "$RESET" "$(_ts)" "$1" >&2; }
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

# --- Phase: Packages ---------------------------------------------------------

# --- Phase: Packages ---------------------------------------------------------
phase_packages() {
  bash "${SCRIPT_DIR}/hyprland-install.sh"
}

# --- Phase: Keyring ---------------------------------------------------------
phase_keyring() {
  bash "${SCRIPT_DIR}/setup-keyring.sh"
}

# --- Phase: Dotfiles ---------------------------------------------------------
phase_dotfiles() {
  local _flags=()
  [[ "${CLOUDYY_UNATTENDED:-0}" == "1" ]] && _flags+=("--unattended")
  bash "${SCRIPT_DIR}/deploy-dotfiles.sh" "${_flags[@]}"
}

# --- Phase: Binary Seeder ----------------------------------------------------
# Symlinks shipped binaries (cloudyy_scripts/cloudyy-other/) into ~/.local/bin/
# so they end up on PATH without a custom export.
phase_bin_seed() {
  bash "${SCRIPT_DIR}/bin_check.sh" seed "$(dirname "${SCRIPT_DIR}")"
}

# --- Phase: Shell Setup -------------------------------------------------------
# Runs after packages so zsh is guaranteed to be installed.
phase_shell() {
  log "Configuring zsh shell..."

  local zsh_path
  zsh_path="$(command -v zsh 2>/dev/null || true)"
  if [[ -z "$zsh_path" ]]; then
    log_warn "zsh not found — skipping (zsh should have been installed in packages phase)."
    return 0
  fi

  if [[ "$SHELL" != "$zsh_path" ]]; then
    if sudo chsh -s "$zsh_path" "$USER" >/dev/null 2>/dev/null; then
      log_ok "Default shell set to zsh (takes effect on next login)."
    else
      log_warn "chsh failed — run: chsh -s ${zsh_path}"
    fi
  else
    log_ok "zsh already default shell."
  fi

  local omz_dir="${HOME}/.config/zsh/oh-my-zsh"
  if [[ ! -d "$omz_dir" ]]; then
    log "Installing oh-my-zsh..."
    local omz_installer
    omz_installer="$(mktemp)"
    if curl -fsSL --connect-timeout 10 --max-time 30 \
         https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
         -o "$omz_installer"; then
      if ZSH="$omz_dir" RUNZSH=no CHSH=no \
           sh "$omz_installer" "" --unattended 2>/dev/null; then
        log_ok "oh-my-zsh installed."
      else
        log_warn "oh-my-zsh install failed — run manually: ZSH=${omz_dir} sh <(curl -s https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
      fi
    else
      log_warn "oh-my-zsh install failed — run manually: ZSH=${omz_dir} sh <(curl -s https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    rm -f "$omz_installer"
  else
    log_ok "oh-my-zsh already installed."
  fi

  # Symlink system-installed plugins into oh-my-zsh custom plugins dir
  local custom_plugins="${omz_dir}/custom/plugins"
  mkdir -p "$custom_plugins"
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    local sys_path="/usr/share/zsh/plugins/${plugin}"
    if [[ -d "$sys_path" && ! -e "${custom_plugins}/${plugin}" ]]; then
      ln -snf "$sys_path" "${custom_plugins}/${plugin}"
      log_ok "Plugin linked: ${plugin}"
    fi
  done

  log_ok "Shell configured."
}

# --- Phase: Schema Settings --------------------------------------------------
phase_schema() {
  local schema_script="${SCRIPT_DIR}/schema_settings.sh"
  if [[ ! -f "$schema_script" ]]; then
    log_warn "schema_settings.sh not found — skipping XDG portal + pywalfox setup."
    return 0
  fi
  bash "$schema_script"
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

  log_ok "Services configured."
}

# --- Phase: Theme Bootstrap --------------------------------------------------
# Runs after packages so matugen is available to generate hyprcolors.conf.
phase_theme_init() {
  local controller="${HOME}/cloudyy_scripts/theme_controller.sh"
  local state_conf="${HOME}/.config/hypr/theme_state/state.conf"
  local default_wall="${HOME}/Wallpapers/Dark/cloudyy.jpg"

  if [[ ! -x "$controller" ]]; then
    log_warn "theme_controller.sh not found — skipping theme bootstrap."
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

  if "$controller" restore >/dev/null 2>&1; then
    log_ok "Theme colours generated."
  else
    log_warn "Theme bootstrap failed (non-fatal — run 'theme_controller.sh restore' later)."
  fi
}

# --- Phase: Finalize ---------------------------------------------------------
phase_finalize() {
  printf '\n%s%s════════════════════════════════════════════%s\n' "$BOLD" "$GREEN" "$RESET"
  printf '%s  🎉  cloudyy-linux installation complete!  %s\n' "$BOLD" "$RESET"
  printf '%s%s════════════════════════════════════════════%s\n\n' "$BOLD" "$GREEN" "$RESET"
  printf 'Log saved to:\n  %s%s%s\n\n' "$CYAN" "$LOG_FILE" "$RESET"

  local config_script="${HOME}/cloudyy_scripts/cloudyy-config"
  if [[ "${UNATTENDED}" != "1" ]] && [[ -x "$config_script" ]]; then
    "$config_script" --first-run
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
  "dotfiles"
  "bin_seed"
  "packages"
  "schema"
  "shell"
  "laptop"
  "keyring"
  "theme_init"
  "services"
  "finalize"
)

declare -A PHASE_LABELS=(
  [preflight]="System Preflight Checks"
  [dotfiles]="Dotfiles Deployment"
  [bin_seed]="Binary Seeder"
  [packages]="Hardware & Package Installation"
  [schema]="XDG Portal & Schema Settings"
  [shell]="Shell Configuration"
  [laptop]="Laptop Hardware Support"
  [keyring]="Keyring Configuration"
  [theme_init]="Initial Theme Bootstrap"
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
    printf 'Usage: %s [--dry-run | --reset | --unattended | --help]\n' "$(basename "$0")"
    printf '\n  --dry-run      Preview phases without making changes\n'
    printf '  --reset        Clear saved progress and start from scratch\n'
    printf '  --unattended   Silent install — skip post-install config prompt\n\n'
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
    local _phase_elapsed=$(( SECONDS - _phase_start ))

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
