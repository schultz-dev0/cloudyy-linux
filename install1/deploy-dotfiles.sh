#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/schultz-dev0/cloudyy-linux"
TARGET_DIR="$HOME/cloudyy-linux"

echo -e "${BLUE}[*] Starting deployment from $REPO_URL...${NC}"

# 1. Clone or Update the repo in home
if [ -d "$TARGET_DIR" ]; then
  echo -e "${BLUE}[*] Updating existing repository...${NC}"
  cd "$TARGET_DIR" && git pull
else
  echo -e "${BLUE}[*] Cloning repository to $HOME...${NC}"
  git clone "$REPO_URL" "$TARGET_DIR"
fi

# 2. Prepare Directories
mkdir -p "$HOME/.config"
mkdir -p "$HOME/.local/bin"

# 3. Create Symlinks
echo -e "${BLUE}[*] Creating symlinks...${NC}"

# Link .config contents (hypr, waybar, kitty, etc.)
# This links every folder inside the repo's .config to your system's .config
if [ -d "$TARGET_DIR/.config" ]; then
  for dir in "$TARGET_DIR/.config"/*; do
    if [ -d "$dir" ]; then
      target="$HOME/.config/$(basename "$dir")"
      rm -rf "$target" # Remove existing to prevent nested links
      ln -sf "$dir" "$target"
      echo -e "${GREEN}[✓] Linked .config/$(basename "$dir")${NC}"
    fi
  done
fi

# Link Wallpapers directly to ~/wallpapers
if [ -d "$TARGET_DIR/wallpapers" ]; then
  rm -rf "$HOME/wallpapers"
  ln -sf "$TARGET_DIR/wallpapers" "$HOME/wallpapers"
  echo -e "${GREEN}[✓] Linked ~/wallpapers${NC}"
fi

# Link Scripts to ~/.local/bin
if [ -d "$TARGET_DIR/scripts" ]; then
  for script in "$TARGET_DIR/scripts"/*; do
    if [ -f "$script" ]; then
      chmod +x "$script"
      ln -sf "$script" "$HOME/.local/bin/$(basename "$script")"
    fi
  done
  echo -e "${GREEN}[✓] Linked scripts to ~/.local/bin${NC}"
fi

echo -e "${GREEN}SUCCESS: Dotfiles deployed and symlinked!${NC}"
