#!/bin/bash

# Hyprland Setup Script for Arch Linux
# Optimized for cloudyy-linux dotfiles

set -e # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# Check if running as root (prevent it)
if [[ $EUID -eq 0 ]]; then
  print_error "This script should not be run as root. Run as normal user with sudo privileges."
  exit 1
fi

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_FILE="$SCRIPT_DIR/dependencies.conf"

if [ ! -f "$DEPS_FILE" ]; then
  print_error "Dependencies file not found: $DEPS_FILE"
  exit 1
fi
source "$DEPS_FILE"

# Setup AUR Helper
check_aur_helper() {
  if ! command -v yay &>/dev/null; then
    print_warning "yay (AUR helper) not found. Installing..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd - || exit
    print_success "yay installed"
  fi
}

# ============================================================================
# PHASE 1: SYSTEM & DRIVERS
# ============================================================================
clear
print_status "Updating system..."
sudo pacman -Syu --noconfirm
check_aur_helper

echo -e "${YELLOW}Hardware Detection:${NC}"
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "GPU: $(lspci | grep -i vga | cut -d: -f3 | xargs)"
echo ""

# GPU Selection
echo "Select your GPU Driver:"
echo "1) NVIDIA (Proprietary/Open DKMS)"
echo "2) AMD (Mesa)"
echo "3) Intel (Mesa)"
echo "4) Skip GPU Drivers"
read -p "Selection [1-4]: " gpu_choice

GPU_PKG=()
case $gpu_choice in
1) GPU_PKG=("${GPU_NVIDIA[@]}") ;;
2) GPU_PKG=("${GPU_AMD[@]}") ;;
3) GPU_PKG=("${GPU_INTEL[@]}") ;;
*) print_warning "Skipping GPU drivers." ;;
esac

# ============================================================================
# PHASE 2: PACKAGE SELECTION
# ============================================================================

# 1. ALWAYS Install Mandatory
INSTALL_LIST=(
  "${CORE_PACKAGES[@]}"
  "${INTERFACE_PACKAGES[@]}"
  "${UTILITY_PACKAGES[@]}"
  "${GPU_PKG[@]}"
)

# 2. ASK for Optionals
echo ""
echo -e "${BLUE}=== Optional Software Groups ===${NC}"

read -p "Install Gaming Suite (Steam, Lutris, etc.)? [y/N]: " opt_game
[[ $opt_game =~ ^[Yy]$ ]] && INSTALL_LIST+=("${OPT_GAMING[@]}")

read -p "Install Social Apps (Discord/Vesktop, Telegram)? [y/N]: " opt_social
[[ $opt_social =~ ^[Yy]$ ]] && INSTALL_LIST+=("${OPT_SOCIAL[@]}")

read -p "Install Creative Tools (OBS, Blender, Gimp)? [y/N]: " opt_create
[[ $opt_create =~ ^[Yy]$ ]] && INSTALL_LIST+=("${OPT_CREATIVE[@]}")

read -p "Install Dev Tools (Code, Git, Node, Docker)? [y/N]: " opt_dev
[[ $opt_dev =~ ^[Yy]$ ]] && INSTALL_LIST+=("${OPT_DEV[@]}")

read -p "Install Music Tools (Spotify, Spicetify)? [y/N]: " opt_music
[[ $opt_music =~ ^[Yy]$ ]] && INSTALL_LIST+=("${OPT_MUSIC[@]}")

read -p "Install Browsers (Firefox, Brave)? [y/N]: " opt_browser
[[ $opt_browser =~ ^[Yy]$ ]] && INSTALL_LIST+=("${OPT_BROWSERS[@]}")

# ============================================================================
# PHASE 3: INSTALLATION LOOP
# ============================================================================
echo ""
print_status "Preparing to install packages..."

# Remove duplicates
UNIQUE_PKGS=($(printf "%s\n" "${INSTALL_LIST[@]}" | sort -u))

OFFICIAL_LIST=()
AUR_LIST=()

# Sort into Repo vs AUR
for pkg in "${UNIQUE_PKGS[@]}"; do
  if pacman -Si "$pkg" &>/dev/null; then
    OFFICIAL_LIST+=("$pkg")
  else
    AUR_LIST+=("$pkg")
  fi
done

# Install Official
if [ ${#OFFICIAL_LIST[@]} -gt 0 ]; then
  print_status "Installing ${#OFFICIAL_LIST[@]} Official Packages..."
  sudo pacman -S --needed --noconfirm "${OFFICIAL_LIST[@]}" || print_error "Batch install failed, trying fallback..."
fi

# Install AUR
if [ ${#AUR_LIST[@]} -gt 0 ]; then
  print_status "Installing ${#AUR_LIST[@]} AUR Packages..."
  yay -S --needed --noconfirm "${AUR_LIST[@]}" || print_error "Batch install failed, trying fallback..."
fi

# ============================================================================
# PHASE 4: FINAL CONFIGS
# ============================================================================

# Services
print_status "Enabling services..."
sudo systemctl enable --now bluetooth.service 2>/dev/null || true
sudo systemctl enable --now ly.service 2>/dev/null || true # If you use ly display manager

# ZRAM
if command -v zram-generator &>/dev/null; then
  print_status "Configuring ZRAM..."
  echo "[zram0]" | sudo tee /etc/systemd/zram-generator.conf >/dev/null
  echo "zram-size = min(ram, 8192)" | sudo tee -a /etc/systemd/zram-generator.conf >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl start systemd-zram-setup@zram0.service
fi

echo ""
print_success "Installation Complete!"
echo "Please reboot your system."
