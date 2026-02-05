#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
REPO_URL="https://github.com/schultz-dev0/cloudyy-linux"
TARGET_DIR="$HOME/cloudyy-linux"

echo -e "${BLUE}[*] Starting deployment from cloudyy-linux...${NC}"

# 1. Clone or Update the repo
if [ -d "$TARGET_DIR" ]; then
  echo -e "${BLUE}[*] Updating existing repository...${NC}"
  cd "$TARGET_DIR" && git pull
else
  echo -e "${BLUE}[*] Cloning repository to $TARGET_DIR...${NC}"
  git clone "$REPO_URL" "$TARGET_DIR"
fi

# 2. Prepare System Directories
mkdir -p "$HOME/.config"

# 3. Symlink Dotfiles to Home (.bashrc, .zshrc, etc.)
echo -e "${BLUE}[*] Symlinking dotfiles to $HOME...${NC}"
find "$TARGET_DIR" -maxdepth 1 -name ".*" -not -name ".git" -not -name ".gitignore" | while read -r dotfile; do
  filename=$(basename "$dotfile")
  ln -sf "$dotfile" "$HOME/$filename"
  echo -e "${GREEN}[✓] Linked $filename to Home${NC}"
done

# 4. Symlink .config Directories (hypr, waybar, etc.)
echo -e "${BLUE}[*] Linking .config directories...${NC}"
if [ -d "$TARGET_DIR/.config" ]; then
  for dir in "$TARGET_DIR/.config"/*; do
    if [ -d "$dir" ]; then
      target="$HOME/.config/$(basename "$dir")"
      rm -rf "$target"
      ln -sf "$dir" "$target"
      echo -e "${GREEN}[✓] Linked .config/$(basename "$dir")${NC}"
    fi
  done
fi

# 5. Symlink Wallpapers to Home
if [ -d "$TARGET_DIR/Wallpapers" ]; then
  rm -rf "$HOME/Wallpapers"
  ln -sf "$TARGET_DIR/Wallpapers" "$HOME/Wallpapers"
  echo -e "${GREEN}[✓] Linked ~/Wallpapers${NC}"
fi

# 6. Symlink cloudyy_scripts to Home
if [ -d "$TARGET_DIR/cloudyy_scripts" ]; then
  rm -rf "$HOME/cloudyy_scripts"
  ln -sf "$TARGET_DIR/cloudyy_scripts" "$HOME/cloudyy_scripts"
  # Ensure all files inside the symlinked folder are executable
  chmod +x "$TARGET_DIR/cloudyy_scripts"/* 2>/dev/null || true
  echo -e "${GREEN}[✓] Linked ~/cloudyy_scripts${NC}"
fi

echo -e "${GREEN}SUCCESS: Complete deployment finished!${NC}"
