#!/usr/bin/env bash
# ==============================================================================
# CLOUDYY SYSTEM UPDATER
# A clean, visual update script inspired by Omarchy
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION ---
readonly AUR_HELPER="${AUR_HELPER:-yay}"
readonly REPO_DIRS=(
  "${HOME}/cloudyy-linux"
)
readonly LOG_DIR="${HOME}/.local/share/system-update"
readonly LOG_FILE="${LOG_DIR}/update_$(date +%Y%m%d_%H%M%S).log"

# --- COLORS & ICONS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
RESET='\033[0m'

ICON_OK="󰄬"
ICON_FAIL="󰅖"
ICON_STEP="󰚰"

# --- UI HELPERS ---
header() {
  clear
  echo -e "${CYAN}"
  echo -e " ░▒▓██████▓▒░░▒▓█▓▒░      ░▒▓██████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓███████▓▒░░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ "
  echo -e "░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ "
  echo -e "░▒▓█▓▒░      ░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░ "
  echo -e "░▒▓█▓▒░      ░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░░▒▓██████▓▒░ ░▒▓██████▓▒░░▒▓█▓▒░ "
  echo -e "░▒▓█▓▒░      ░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░      ░▒▓█▓▒░   ░▒▓█▓▒░ "
  echo -e "░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░     ░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░▒▓█▓▒░░▒▓█▓▒░  ░▒▓█▓▒░      ░▒▓█▓▒░           "
  echo -e " ░▒▓██████▓▒░░▒▓████████▓▒░▒▓██████▓▒░ ░▒▓██████▓▒░░▒▓███████▓▒░   ░▒▓█▓▒░      ░▒▓█▓▒░   ░▒▓█▓▒░"
  echo -e "${RESET}"
  echo -e "${BOLD}${WHITE}    Cloudyy Linux  •  $(date '+%A, %d %B')${RESET}\n"
}

step_start() {
  printf " ${CYAN}${ICON_STEP}${RESET}  %-30s" "$1..."
}

step_ok() {
  printf "\r ${GREEN}${ICON_OK}${RESET}  %-30s  ${GREEN}${BOLD}DONE${RESET}\n" "$1"
}

step_fail() {
  printf "\r ${RED}${ICON_FAIL}${RESET}  %-30s  ${RED}${BOLD}FAILED${RESET}\n" "$1"
}

# --- UPDATE LOGIC ---

update_system() {
  step_start "System Packages"
  if sudo pacman -Syu --noconfirm >/dev/null 2>&1; then
    step_ok "System Packages"
  else
    step_fail "System Packages"
    return 1
  fi
}

update_aur() {
  if ! command -v "$AUR_HELPER" >/dev/null 2>&1; then return 0; fi
  step_start "AUR Packages"
  if "$AUR_HELPER" -Syu --aur --noconfirm >/dev/null 2>&1; then
    step_ok "AUR Packages"
  else
    step_fail "AUR Packages"
    return 1
  fi
}

update_repos() {
  # Commented out for now as requested
  # for repo in "${REPO_DIRS[@]}"; do
  #   repo="${repo/#\~/$HOME}"
  #   [[ -d "$repo" ]] || continue
  #   local name=$(basename "$repo")
  #   step_start "Git Repo: $name"
  #   if (cd "$repo" && git fetch --all && git pull --ff-only) >/dev/null 2>&1; then
  #     step_ok "Git Repo: $name"
  #   else
  #     step_fail "Git Repo: $name"
  #   fi
  # done
  return 0
}

clean_up() {
  step_start "Cleaning Cache"
  if command -v paccache >/dev/null 2>&1; then
    sudo paccache -rk2 >/dev/null 2>&1
  fi
  "$AUR_HELPER" -Sc --noconfirm >/dev/null 2>&1 || true
  step_ok "Cleaning Cache"
}

# --- MAIN ---

header

echo -e "  ${BOLD}Do you want to update?${RESET}"
echo -e "  [y] Yes / [n] No"
echo -ne "\n  > "
read -n 1 -r CONFIRM
echo -e "\n"

if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
  echo -e "  ${YELLOW}Update cancelled.${RESET}\n"
  exit 0
fi

# Authenticate sudo AFTER confirmation
echo -e "  ${BOLD}Authenticating...${RESET}"
sudo -v

# Keep sudo alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# Start logging
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# Network Check
if ! ping -c 1 -W 2 archlinux.org >/dev/null 2>&1; then
  echo -e " ${RED}${ICON_FAIL}  No network connection detected. Exiting.${RESET}\n"
  exit 1
fi

update_system || true
update_aur || true
update_repos
clean_up

echo -e "\n${GREEN}${BOLD}  ✨ System fully updated!${RESET}\n"
echo -e "  ${CYAN}Log:${RESET} ${LOG_FILE}\n"
