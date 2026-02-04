#!/bin/bash
# Hyprland Setup Script for Arch Linux - Part 2: Dotfiles Deployment
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[*]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# ============================================================================
# CONFIGURATION - YOUR REPO HARDCODED
# ============================================================================
DOTFILES_REPO="https://github.com/schultz-dev0/cloudyy-linux"
DOTFILES_DIR="$HOME/cloudyy-linux"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config_backup_$(date +%Y%m%d_%H%M%S)"

clear
echo -e "${GREEN}Deploying cloudyy-linux configurations...${NC}"

# Clone the repository
if [ -d "$DOTFILES_DIR" ]; then
  print_status "Local repository found. Pulling latest changes..."
  cd "$DOTFILES_DIR" && git pull
else
  print_status "Cloning from $DOTFILES_REPO..."
  git clone "$DOTFILES_REPO" "$DOTFILES_DIR"
fi

# Backup existing configs
print_status "Creating backup at $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
for config in hypr waybar kitty mako wofi swaync; do
  if [ -d "$CONFIG_DIR/$config" ]; then
    mv "$CONFIG_DIR/$config" "$BACKUP_DIR/"
  fi
done

# Deployment Logic (Using Symlinks as default for easier editing)
print_status "Linking configurations..."
mkdir -p "$CONFIG_DIR"

# List of folders in your repo to link to ~/.config/
# Adjust this list based on exactly what folders are in your cloudyy-linux repo
CONFIG_FOLDERS=("hypr" "waybar" "kitty" "mako" "swaync")

for folder in "${CONFIG_FOLDERS[@]}"; do
  if [ -d "$DOTFILES_DIR/$folder" ]; then
    ln -sf "$DOTFILES_DIR/$folder" "$CONFIG_DIR/$folder"
    print_success "Linked $folder"
  fi
done

print_success "Dotfiles deployed successfully from cloudyy-linux!"
