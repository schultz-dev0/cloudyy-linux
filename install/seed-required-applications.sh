#!/usr/bin/env bash
set -euo pipefail -E

# Seeds only required desktop entries into the user's local applications dir.
# Usage:
#   seed-required-applications.sh [repo_dir]

readonly REPO_DIR="${1:-${HOME}/cloudyy-linux}"
readonly LEGACY_SOURCE_DIR="${REPO_DIR}/.local/share/applications"
readonly TARGET_DIR="${HOME}/.local/share/applications"
readonly ASSET_SOURCE_DIR="${REPO_DIR}/install/.app-assets/icons"
readonly ICON_TARGET_DIR="${HOME}/.local/share/icons/cloudyy-apps"

if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' DIM=$'\e[2m' BOLD=$'\e[1m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' DIM='' BOLD='' RESET=''
fi

_ts() { date '+%H:%M:%S'; }
log_ok()   { printf '%s[✓]%s  [%s] %s\n' "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_warn() { printf '%s[!]%s  [%s] %s\n' "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_write(){ printf '%s[+]%s  [%s] %s\n' "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_error(){ printf '%s[✗]%s  [%s] %s\n' "$RED"    "$RESET" "$(_ts)" "$1" >&2; }

_err_handler() {
  log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  log_error "  in ${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}:${FUNCNAME[1]:-main}"
}
trap '_err_handler' ERR

install_icon_asset() {
  local file_name="$1"
  local fallback_icon="$2"
  local src="${ASSET_SOURCE_DIR}/${file_name}"
  local dst="${ICON_TARGET_DIR}/${file_name}"

  if [[ -f "$src" ]]; then
    install -m 0644 "$src" "$dst"
    log_ok "Installed icon: ${file_name}" >&2
    printf '%s' "$dst"
    return 0
  fi

  log_warn "Icon asset missing (${file_name}), using fallback icon: ${fallback_icon}" >&2
  printf '%s' "$fallback_icon"
}

mkdir -p "${HOME}/.local/share"
mkdir -p "${HOME}/.local/share/icons"

# If applications is linked to repo content, unlink so each user owns their own dir.
if [[ -L "$TARGET_DIR" ]]; then
  link_dest="$(readlink -f "$TARGET_DIR" 2>/dev/null || true)"
  if [[ "$link_dest" == "${LEGACY_SOURCE_DIR}" ]]; then
    rm -f "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
    log_ok "Unlinked repo-managed applications directory."
  fi
fi

mkdir -p "$TARGET_DIR"
mkdir -p "$ICON_TARGET_DIR"

aichat_icon="$(install_icon_asset "openwebui.svg" "applications-internet")"
rusty_keys_icon="$(install_icon_asset "rustykeys.svg" "input-keyboard")"
cloud_center_icon="$(install_icon_asset "cloud-center.svg" "utilities-system-monitor")"

cat >"${TARGET_DIR}/aichat.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=AIChat
Comment=Open WebUI for Local AI
Exec=firefoxpwa site launch 01KJ95M10ZZ3KV0ZENF0EJ3XMY
Icon=${aichat_icon}
Terminal=false
Categories=Network;ArtificialIntelligence;
Keywords=AI;Chat;DeepSeek;Ollama;
EOF
chmod 0644 "${TARGET_DIR}/aichat.desktop"
log_write "Created: aichat.desktop"

cat >"${TARGET_DIR}/nvim.desktop" <<'EOF'
[Desktop Entry]
Name=Neovim
Exec=kitty -e nvim %F
Type=Application
Terminal=false
Icon=nvim
MimeType=text/plain;
Categories=Development;TextEditor;
EOF
chmod 0644 "${TARGET_DIR}/nvim.desktop"
log_write "Created: nvim.desktop"

cat >"${TARGET_DIR}/rusty_keys.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Rusty Keys
Comment=Mechanical keyboard sound daemon
Exec=bash -c "~/cloudyy_scripts/cloudyy-other/rusty_keys"
Icon=${rusty_keys_icon}
Terminal=false
Categories=Utility;
StartupNotify=false
StartupWMClass=org.cloudyy.rustykeys
X-GNOME-WMClass=org.cloudyy.rustykeys
EOF
chmod 0644 "${TARGET_DIR}/rusty_keys.desktop"
log_write "Created: rusty_keys.desktop"

cat >"${TARGET_DIR}/Cloud-center.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Cloud Center
Comment=Cloud Center — Hyprland session manager
Exec=bash -c "python3 ~/cloudyy_scripts/cloud-center-v2/cloud-center.py"
Icon=${cloud_center_icon}
Terminal=false
Categories=Utility;System;
StartupNotify=false
StartupWMClass=org.cloudyy.cloudcenter
X-GNOME-WMClass=org.cloudyy.cloudcenter
EOF
chmod 0644 "${TARGET_DIR}/Cloud-center.desktop"
log_write "Created: Cloud-center.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
fi
