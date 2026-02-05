#!/bin/bash

# Hyprland Setup Script for Arch Linux
# Part 1: Hardware Detection and Driver Installation

set -e # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_status() {
  echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
  echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[!]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  print_error "This script should not be run as root. Run as normal user with sudo privileges."
  exit 1
fi

# Check if yay is installed (AUR helper)
check_aur_helper() {
  if ! command -v yay &>/dev/null; then
    print_warning "yay (AUR helper) not found. Installing..."
    sudo pacman -S --needed --noconfirm git base-devel
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    print_success "yay installed successfully"
  else
    print_success "yay is already installed"
  fi
}

# Display header
clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Hyprland Setup Script - Arch Linux      ║${NC}"
echo -e "${GREEN}║   Part 1: Hardware & Driver Installation  ║${NC}"
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo ""

# Update system first
print_status "Updating system packages..."
sudo pacman -Syu --noconfirm
print_success "System updated"

# Install AUR helper
check_aur_helper

# Detect and display current hardware
print_status "Detecting current hardware..."
echo ""
echo -e "${YELLOW}Current System Information:${NC}"
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "GPU: $(lspci | grep -i vga | cut -d: -f3 | xargs)"
echo ""

# CPU Selection
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}CPU Microcode Selection${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo "1) Intel CPU"
echo "2) AMD CPU"
echo "3) Skip CPU microcode"
echo ""
read -p "Select your CPU type [1-3]: " cpu_choice

case $cpu_choice in
1)
  print_status "Installing Intel microcode..."
  sudo pacman -S --needed --noconfirm intel-ucode
  print_success "Intel microcode installed"
  ;;
2)
  print_status "Installing AMD microcode..."
  sudo pacman -S --needed --noconfirm amd-ucode
  print_success "AMD microcode installed"
  ;;
3)
  print_warning "Skipping CPU microcode installation"
  ;;
*)
  print_error "Invalid selection, skipping..."
  ;;
esac

# GPU Selection
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}GPU Driver Selection${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo "1) Intel iGPU (integrated graphics)"
echo "2) AMD GPU"
echo "3) NVIDIA GPU (open drivers)"
echo "4) Skip GPU drivers"
echo ""
read -p "Select your GPU type [1-4]: " gpu_choice

case $gpu_choice in
1)
  print_status "Installing Intel iGPU drivers..."
  sudo pacman -S --needed --noconfirm mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver
  print_success "Intel iGPU drivers installed"
  ;;
2)
  print_status "Installing AMD GPU drivers..."
  sudo pacman -S --needed --noconfirm mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon libva-mesa-driver lib32-libva-mesa-driver
  print_success "AMD GPU drivers installed"
  ;;
3)
  print_status "Installing NVIDIA GPU drivers..."
  sudo pacman -S --needed --noconfirm nvidia-open-dkms nvidia-utils lib32-nvidia-utils nvidia-settings
  yay -S --needed --noconfirm wlroots-nvidia
  print_warning "IMPORTANT: You need to add NVIDIA modules to mkinitcpio.conf"
  print_warning "Add this line: MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
  print_warning "Then run: sudo mkinitcpio -P"
  print_warning "You may also need kernel parameters: nvidia-drm.modeset=1"
  ;;
4)
  print_warning "Skipping GPU driver installation"
  ;;
*)
  print_error "Invalid selection, skipping..."
  ;;
esac

# Wireless/Bluetooth firmware
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}Wireless & Bluetooth Firmware${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo "Do you need wireless/Bluetooth firmware?"
echo "1) Yes - Install common firmware (Broadcom, Intel, etc.)"
echo "2) MacBook specific firmware (Broadcom)"
echo "3) Skip"
echo ""
read -p "Select option [1-3]: " wireless_choice

case $wireless_choice in
1)
  print_status "Installing common wireless firmware..."
  sudo pacman -S --needed --noconfirm linux-firmware
  yay -S --needed --noconfirm broadcom-wl-dkms
  print_success "Wireless firmware installed"
  ;;
2)
  print_status "Installing MacBook specific firmware..."
  sudo pacman -S --needed --noconfirm linux-firmware
  yay -S --needed --noconfirm broadcom-wl-dkms
  print_success "MacBook firmware installed"
  ;;
3)
  print_warning "Skipping wireless firmware installation"
  ;;
*)
  print_error "Invalid selection, skipping..."
  ;;
esac

# Load dependencies configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_FILE="$SCRIPT_DIR/dependencies.conf"

if [ ! -f "$DEPS_FILE" ]; then
  print_error "Dependencies file not found: $DEPS_FILE"
  print_warning "Using fallback minimal package list..."
  FALLBACK_PACKAGES=(
    "hyprland" "kitty" "waybar" "wofi" "dunst"
    "xdg-desktop-portal-hyprland" "qt5-wayland" "qt6-wayland"
    "polkit-kde-agent" "pipewire" "wireplumber" "pipewire-audio"
    "pipewire-pulse" "grim" "slurp" "wl-clipboard"
  )
else
  print_success "Loading dependencies from $DEPS_FILE"
  source "$DEPS_FILE"
fi

# Ask user which package group to install
echo ""
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo -e "${YELLOW}Package Installation Selection${NC}"
echo -e "${BLUE}═══════════════════════════════════════${NC}"
echo "1) Minimal - Only essential packages (~30 packages)"
echo "2) Standard - Recommended setup (~80 packages)"
echo "3) Full - Everything including optional apps (~120+ packages)"
echo "4) Custom - Choose package categories manually"
echo ""
read -p "Select installation type [1-4]: " install_type

case $install_type in
1)
  print_status "Installing minimal package set..."
  if [ -f "$DEPS_FILE" ]; then
    PACKAGES_TO_INSTALL=("${MINIMAL_GROUP[@]}")
  else
    PACKAGES_TO_INSTALL=("${FALLBACK_PACKAGES[@]}")
  fi
  ;;
2)
  print_status "Installing standard package set..."
  PACKAGES_TO_INSTALL=("${STANDARD_GROUP[@]}")
  ;;
3)
  print_status "Installing full package set..."
  PACKAGES_TO_INSTALL=("${FULL_GROUP[@]}")
  ;;
4)
  print_status "Custom installation selected..."
  PACKAGES_TO_INSTALL=()

  echo ""
  echo "Select package categories to install:"

  read -p "Install CORE packages (required)? [Y/n]: " core_choice
  [[ ! $core_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${CORE_PACKAGES[@]}")

  read -p "Install TERMINAL packages? [Y/n]: " term_choice
  [[ ! $term_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${TERMINAL_PACKAGES[@]}")

  read -p "Install AUDIO packages? [Y/n]: " audio_choice
  [[ ! $audio_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${AUDIO_PACKAGES[@]}")

  read -p "Install INTERFACE packages (waybar, wofi, etc.)? [Y/n]: " interface_choice
  [[ ! $interface_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${INTERFACE_PACKAGES[@]}")

  read -p "Install FILE MANAGEMENT packages? [Y/n]: " file_choice
  [[ ! $file_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${FILE_PACKAGES[@]}")

  read -p "Install SCREENSHOT packages? [Y/n]: " screenshot_choice
  [[ ! $screenshot_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${SCREENSHOT_PACKAGES[@]}")

  read -p "Install CLIPBOARD packages? [Y/n]: " clipboard_choice
  [[ ! $clipboard_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${CLIPBOARD_PACKAGES[@]}")

  read -p "Install UTILITY packages? [Y/n]: " utility_choice
  [[ ! $utility_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${UTILITY_PACKAGES[@]}")

  read -p "Install FONT packages? [Y/n]: " font_choice
  [[ ! $font_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${FONT_PACKAGES[@]}")

  read -p "Install DEVELOPMENT packages? [Y/n]: " dev_choice
  [[ ! $dev_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${DEV_PACKAGES[@]}")

  read -p "Install APPLICATION packages? [Y/n]: " app_choice
  [[ ! $app_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${APP_PACKAGES[@]}")

  read -p "Install THEME packages? [Y/n]: " theme_choice
  [[ ! $theme_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${THEME_PACKAGES[@]}")

  read -p "Install CUSTOM packages? [Y/n]: " custom_choice
  [[ ! $custom_choice =~ ^[Nn]$ ]] && PACKAGES_TO_INSTALL+=("${CUSTOM_PACKAGES[@]}")
  ;;
*)
  print_error "Invalid selection, using standard installation"
  PACKAGES_TO_INSTALL=("${STANDARD_GROUP[@]}")
  ;;
esac

# ============================================================================
# SMART PACKAGE INSTALLATION
# ============================================================================
echo ""
print_status "Processing ${#PACKAGES_TO_INSTALL[@]} packages..."
echo ""

# Remove duplicates
UNIQUE_PACKAGES=($(printf "%s\n" "${PACKAGES_TO_INSTALL[@]}" | sort -u | grep -v '^$'))

# Lists to separate official vs AUR packages
OFFICIAL_LIST=()
AUR_LIST=()

print_status "Sorting packages into Official and AUR lists..."

for pkg in "${UNIQUE_PACKAGES[@]}"; do
  # Check if package exists in official repos
  if pacman -Si "$pkg" &>/dev/null; then
    OFFICIAL_LIST+=("$pkg")
  else
    # If not found in pacman, assume it's AUR
    print_warning "Package '$pkg' not found in official repos. Moving to AUR list."
    AUR_LIST+=("$pkg")
  fi
done

# 1. Install Official Packages (Batch mode for speed)
if [ ${#OFFICIAL_LIST[@]} -gt 0 ]; then
  print_status "Installing ${#OFFICIAL_LIST[@]} official packages..."
  sudo pacman -S --needed --noconfirm "${OFFICIAL_LIST[@]}" || {
    print_error "Pacman failed. Trying to install one by one..."
    # Fallback: Install one by one if batch fails
    for pkg in "${OFFICIAL_LIST[@]}"; do
      sudo pacman -S --needed --noconfirm "$pkg" || print_error "Failed to install $pkg"
    done
  }
  print_success "Official packages installed."
fi

# 2. Install AUR Packages (Batch mode)
if [ ${#AUR_LIST[@]} -gt 0 ]; then
  print_status "Installing ${#AUR_LIST[@]} AUR packages..."
  yay -S --needed --noconfirm "${AUR_LIST[@]}" || {
    print_error "AUR install failed. Trying one by one..."
    for pkg in "${AUR_LIST[@]}"; do
      yay -S --needed --noconfirm "$pkg" || print_error "Failed to install $pkg"
    done
  }
  print_success "AUR packages installed."
fi

# Install Python packages
if [ -f "$DEPS_FILE" ] && [ ${#PYTHON_PACKAGES[@]} -gt 0 ]; then
  echo ""
  read -p "Do you want to install Python packages? [y/N]: " python_choice
  if [[ $python_choice =~ ^[Yy]$ ]]; then
    print_status "Installing Python packages..."
    for pkg in "${PYTHON_PACKAGES[@]}"; do
      if [ -n "$pkg" ]; then
        print_status "Installing Python package: $pkg"
        pip install --user "$pkg" --break-system-packages || {
          print_warning "Failed to install $pkg, skipping..."
        }
      fi
    done
    print_success "Python packages installation completed"
  else
    print_warning "Skipping Python packages"
  fi
fi

print_success "All package installations completed"

# Install optional packages
if [ -f "$DEPS_FILE" ] && [ ${#OPTIONAL_PACKAGES[@]} -gt 0 ]; then
  # Count non-commented optional packages
  OPTIONAL_COUNT=0
  for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    if [[ ! "$pkg" =~ ^#.*$ ]] && [ -n "$pkg" ]; then
      ((OPTIONAL_COUNT++))
    fi
  done

  if [ $OPTIONAL_COUNT -gt 0 ]; then
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo -e "${YELLOW}Optional Packages Available${NC}"
    echo -e "${BLUE}═══════════════════════════════════════${NC}"
    echo "The following optional packages are uncommented in dependencies.conf:"
    for pkg in "${OPTIONAL_PACKAGES[@]}"; do
      if [[ ! "$pkg" =~ ^#.*$ ]] && [ -n "$pkg" ]; then
        echo "  - $pkg"
      fi
    done
    echo ""
    read -p "Do you want to install these optional packages? [y/N]: " optional_choice
    if [[ $optional_choice =~ ^[Yy]$ ]]; then
      print_status "Installing optional packages..."
      for pkg in "${OPTIONAL_PACKAGES[@]}"; do
        if [[ ! "$pkg" =~ ^#.*$ ]] && [ -n "$pkg" ]; then
          print_status "Installing: $pkg"
          # Try pacman first, then yay if it fails
          if ! sudo pacman -S --needed --noconfirm "$pkg" 2>/dev/null; then
            yay -S --needed --noconfirm "$pkg" || {
              print_warning "Failed to install $pkg, skipping..."
            }
          fi
        fi
      done
      print_success "Optional packages installation completed"
    else
      print_warning "Skipping optional packages"
      print_info "To install later, uncomment packages in dependencies.conf and re-run"
    fi
  else
    print_info "No optional packages are enabled in dependencies.conf"
    print_info "Edit dependencies.conf and uncomment packages in OPTIONAL_PACKAGES section"
  fi
fi

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Hardware Setup Complete!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
print_success "Hardware drivers and firmware installed successfully"
echo ""
print_status "Next step: Deploy dotfiles and configurations"
echo ""

# Ask if user wants to continue to dotfiles deployment
read -p "Would you like to continue to dotfiles deployment? (y/n): " continue_choice

if [[ $continue_choice =~ ^[Yy]$ ]]; then
  echo ""
  print_status "Dotfiles deployment will be implemented next..."
  print_warning "This section is not yet implemented. Please run the dotfiles script separately."
else
  print_status "Installation paused. Run this script again to continue with dotfiles."
fi

echo ""
print_success "Script completed successfully!"
