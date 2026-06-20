#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (use sudo)"
  exit 1
fi

# 1. Get the target username
TARGET_USER=${1:-$SUDO_USER}
if [ -z "$TARGET_USER" ]; then
  echo "Usage: sudo ./optimize-boot.sh [username]"
  exit 1
fi

echo "--- Starting Portable System Optimization for: $TARGET_USER ---"

# 2. Fix Limine Path & Timeout
LIMINE_CFG="/boot/limine/limine.conf"
if [ -f "$LIMINE_CFG" ]; then
  echo "Optimizing Limine at $LIMINE_CFG..."
  # Remove any existing timeout lines to prevent duplicates
  sed -i '/^timeout:/d' "$LIMINE_CFG"
  sed -i '/^TIMEOUT:/d' "$LIMINE_CFG"
  # Insert timeout: 0 at the very top of the file
  sed -i '1i timeout: 0' "$LIMINE_CFG"
else
  echo "Warning: Limine config not found at $LIMINE_CFG"
fi

# 3. Setup Getty Autologin Override (Bypass TTY Password)
echo "Configuring TTY1 Autologin..."
GETTY_DIR="/etc/systemd/system/getty@tty1.service.d"
mkdir -p "$GETTY_DIR"
cat <<EOF >"$GETTY_DIR/autologin.conf"
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF

# 4. Global Hyprland Auto-start (Zsh)
echo "Setting up global Zsh Hyprland auto-start..."
ZPROFILE="/etc/zsh/zprofile"
mkdir -p /etc/zsh
if ! grep -qE "uwsm|Hyprland|hyprland" "$ZPROFILE" 2>/dev/null; then
  cat <<'EOF' >>"$ZPROFILE"

# Auto-start Hyprland on TTY1 via UWSM
if [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-0}" -eq 1 ] && uwsm check may-start 2>/dev/null; then
  exec uwsm start hyprland-uwsm.desktop
fi
EOF
fi

# 5. Mask NetworkManager Delay & Optimize Docker
echo "Cutting Userspace delays..."
systemctl mask NetworkManager-wait-online.service
if systemctl list-unit-files | grep -q "docker.service"; then
  systemctl disable docker.service
  systemctl enable docker.socket
fi

echo "Rebuilding initramfs..."
mkinitcpio -P

echo "--- Optimization Complete! ---"
