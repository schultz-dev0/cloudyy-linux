#!/bin/bash

# Hyprland Complete Setup Script for Arch Linux
# Master installer that runs both hardware setup and dotfiles deployment

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

# Display header
clear
echo -e "${GREEN}"
cat <<"EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║        Hyprland Complete Setup - Arch Linux              ║
║                                                          ║
║        Hardware Detection → Driver Installation          ║
║               → Dotfiles Deployment                      ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  print_error "This script should not be run as root. Run as normal user with sudo privileges."
  exit 1
fi

# Check for sudo privileges
if ! sudo -v; then
  print_error "This script requires sudo privileges. Please ensure you have sudo access."
  exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if sub-scripts exist
if [ ! -f "$SCRIPT_DIR/hyprland-install.sh" ]; then
  print_error "hyprland-install.sh not found in $SCRIPT_DIR"
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/deploy-dotfiles.sh" ]; then
  print_error "deploy-dotfiles.sh not found in $SCRIPT_DIR"
  exit 1
fi

# Make scripts executable
chmod +x "$SCRIPT_DIR/hyprland-install.sh"
chmod +x "$SCRIPT_DIR/deploy-dotfiles.sh"

echo ""
print_status "This script will:"
echo "  1. Detect your hardware and install necessary drivers"
echo "  2. Install Hyprland and essential packages"
echo "  3. Deploy your dotfiles and configurations"
echo ""
print_warning "This process may take some time. Please be patient."
echo ""

read -p "Do you want to continue? (y/n): " continue_choice

if [[ ! $continue_choice =~ ^[Yy]$ ]]; then
  print_status "Installation cancelled by user."
  exit 0
fi

# Run hardware installation
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         STEP 1: Hardware & Driver Installation        ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

if ! bash "$SCRIPT_DIR/hyprland-install.sh"; then
  print_error "Hardware installation failed. Please check the errors above."
  exit 1
fi

print_success "Hardware installation completed!"
echo ""
sleep 2

# Run dotfiles deployment
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           STEP 2: Dotfiles Deployment                 ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

if ! bash "$SCRIPT_DIR/deploy-dotfiles.sh"; then
  print_error "Dotfiles deployment failed. Please check the errors above."
  exit 1
fi

# Final summary
echo ""
echo -e "${GREEN}"
cat <<"EOF"
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║             🎉 Installation Complete! 🎉                 ║
║                                                          ║
║     Your Hyprland setup is ready to use!                ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

echo ""
print_success "All steps completed successfully!"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Log out of your current session"
echo "  2. Select Hyprland from your display manager"
echo "  3. Log in and enjoy your new setup!"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo "  • Start Hyprland manually: Hyprland"
echo "  • Edit Hyprland config: nano ~/.config/hypr/hyprland.conf"
echo "  • View logs: cat ~/.hyprland.log"
echo ""
print_status "Thank you for using this setup script!"
echo ""
