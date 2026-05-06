# Installer Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the interactive 20-question installer with a silent, opinionated install plus a re-runnable `cloudyy-config` tool for post-install swaps and add-ons.

**Architecture:** `install/lib.sh` holds shared utilities (colours, logging, `pacman_install`, `aur_install`) sourced by both `hyprland-install.sh` and `cloudyy-config`. `hyprland-install.sh` becomes a ~200-line silent installer. `cloudyy-config` in `cloudyy_scripts/` handles all post-install customisation. `install.sh` gains `--unattended` to skip even the first-run config prompt.

**Tech Stack:** Bash 5, pacman, yay (AUR helper), shellcheck (linting)

**Branch:** `dev` — all commits go here.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `install/lib.sh` | **CREATE** | Colours, logging helpers, `pacman_install()`, `aur_install()`, `AUR_HELPER` var |
| `install/dependencies.conf` | **MODIFY** | Add `STANDARD_INSTALL_*`, `SWAPPABLE_*`, `ADDON_*`; move tesseract to mandatory; remove `CHOICE_*` / `OPTIONAL_*` |
| `install/hyprland-install.sh` | **REWRITE** | Silent: source lib.sh, auto AUR helper, auto GPU detect, install mandatory + standard |
| `cloudyy_scripts/cloudyy-config` | **CREATE** | Re-runnable swap/manage tool with `--first-run` mode |
| `install/install.sh` | **MODIFY** | Add `--unattended` flag; call `cloudyy-config --first-run` in `phase_finalize` |

---

## Task 1: Create install/lib.sh

**Files:**
- Create: `install/lib.sh`

- [ ] **Step 1: Write lib.sh**

```bash
#!/usr/bin/env bash
# =============================================================================
# lib.sh — Shared utilities for cloudyy-linux install scripts
# Source this file; do not execute directly.
# =============================================================================
[[ -n "${_CLOUDYY_LIB_LOADED:-}" ]] && return 0
_CLOUDYY_LIB_LOADED=1

# --- Colors (TTY-aware) -------------------------------------------------------
if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m'
  BLUE=$'\e[1;34m' CYAN=$'\e[1;36m' BOLD=$'\e[1m'
  DIM=$'\e[2m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

# --- Logging ------------------------------------------------------------------
log()         { printf '%s[*]%s %s\n'    "$BLUE"   "$RESET" "$1"; }
log_ok()      { printf '%s[✓]%s %s\n'   "$GREEN"  "$RESET" "$1"; }
log_warn()    { printf '%s[!]%s %s\n'   "$YELLOW" "$RESET" "$1"; }
log_error()   { printf '%s[✗]%s %s\n'   "$RED"    "$RESET" "$1" >&2; }
log_skip()    { printf '%s[-]%s %s\n'   "$DIM"    "$RESET" "$1"; }
log_section() { printf '\n%s%s── %s%s\n' "$BOLD"  "$CYAN"  "$1" "$RESET"; }
divider()     { printf '%s─────────────────────────────────────────────%s\n' "$DIM" "$RESET"; }

# --- AUR Helper (set by setup_aur_helper in hyprland-install.sh) -------------
AUR_HELPER=""

# --- Package Installation -----------------------------------------------------
pacman_install() {
  local group="$1"; shift
  local -a pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  log "pacman [${group}] — ${#pkgs[@]} pkg(s)"
  if sudo pacman -S --needed --noconfirm "${pkgs[@]}"; then
    log_ok "${group}"
    return 0
  fi
  log_warn "${group} — batch failed, retrying individually..."
  local fails=0
  for pkg in "${pkgs[@]}"; do
    if sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
      log_ok "  ✓ ${pkg}"
    else
      log_warn "  ✗ ${pkg}"
      fails=$(( fails + 1 ))
    fi
  done
  (( fails > 0 )) && log_warn "${group}: ${fails} package(s) skipped." || true
  return 0
}

aur_install() {
  local group="$1"; shift
  local -a pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  if [[ -z "$AUR_HELPER" ]]; then
    log_warn "No AUR helper — skipping [${group}]"
    return 0
  fi
  log "${AUR_HELPER} [${group}] — ${#pkgs[@]} pkg(s)"
  if "$AUR_HELPER" -S --needed --noconfirm "${pkgs[@]}"; then
    log_ok "${group}"
    return 0
  fi
  log_warn "${group} — batch failed, retrying individually..."
  local fails=0
  for pkg in "${pkgs[@]}"; do
    if "$AUR_HELPER" -S --needed --noconfirm "$pkg" &>/dev/null; then
      log_ok "  ✓ ${pkg}"
    else
      log_warn "  ✗ ${pkg}"
      fails=$(( fails + 1 ))
    fi
  done
  (( fails > 0 )) && log_warn "${group}: ${fails} package(s) skipped." || true
  return 0
}
```

- [ ] **Step 2: Verify syntax and lint**

```bash
bash -n install/lib.sh && echo "syntax OK"
shellcheck install/lib.sh
```

Expected: no errors. If shellcheck is not installed: `sudo pacman -S --needed shellcheck`.

- [ ] **Step 3: Verify double-source guard works**

```bash
bash -c 'source install/lib.sh; source install/lib.sh; log "loaded once"; echo exit:$?'
```

Expected output: `[*] loaded once` printed once, `exit:0`.

- [ ] **Step 4: Commit**

```bash
git add install/lib.sh
git commit -m "feat: add install/lib.sh — shared colours, logging, pacman/aur install fns"
```

---

## Task 2: Update dependencies.conf

**Files:**
- Modify: `install/dependencies.conf`

This task replaces all `CHOICE_*` and `OPTIONAL_*` arrays with `STANDARD_INSTALL_*`, `SWAPPABLE_*`, and `ADDON_*` blocks, and moves `tesseract` / `tesseract-data-eng` into mandatory.

- [ ] **Step 1: Add tesseract to MANDATORY_OFFICIAL_SYSTEM**

In `install/dependencies.conf`, find the `MANDATORY_OFFICIAL_SYSTEM` array and add to it:

```bash
  "tesseract"          # OCR engine (used by clipboard scripts)
  "tesseract-data-eng" # English OCR data
```

- [ ] **Step 2: Replace CHOICE_* and OPTIONAL_* with new arrays**

Delete everything from the line `# =============================================================================`
`# CHOICES — pick exactly one per category` through the end of `FULL_GROUP=(...)`.

Replace with the following (paste in full):

```bash
# =============================================================================
# STANDARD INSTALL — installed on every machine beyond MANDATORY
# =============================================================================

STANDARD_INSTALL_OFFICIAL=(
  # Terminal & multiplexer
  "kitty"
  "zellij"

  # File manager
  "thunar" "thunar-archive-plugin" "thunar-volman" "tumbler"
  "gvfs" "gvfs-mtp" "gvfs-nfs" "gvfs-smb" "file-roller"

  # CLI toolkit
  "neovim" "bat" "eza" "fzf" "ripgrep" "fd" "yazi" "tealdeer"
  "imagemagick" "reflector" "tree" "gdu" "swayimg" "inxi" "expac"

  # GUI extras
  "blueman" "gnome-calculator" "gnome-clocks" "loupe" "seahorse"
  "gparted" "udiskie" "yad" "xdg-user-dirs"

  # Phone integration
  "kdeconnect"

  # Notes
  "obsidian"

  # System tools
  "btrfs-progs" "snapper" "ntfs-3g" "efibootmgr" "usbutils"
  "arch-wiki-docs" "localsend"
)

STANDARD_INSTALL_AUR=(
  "zen-browser-bin"
  "vesktop"
  "spotify"
  "spicetify-cli"
)

# =============================================================================
# SWAPPABLE — cloudyy-config reads these to know current default + alternatives
# =============================================================================

SWAPPABLE_BROWSER_DEFAULT="zen-browser-bin"
SWAPPABLE_BROWSER_DEFAULT_TYPE="aur"
SWAPPABLE_BROWSER=(
  "zen-browser-bin|Zen Browser|aur"
  "firefox|Firefox|official"
  "brave-bin|Brave|aur"
  "chromium|Chromium|official"
)

SWAPPABLE_TERMINAL_DEFAULT="kitty"
SWAPPABLE_TERMINAL_DEFAULT_TYPE="official"
SWAPPABLE_TERMINAL=(
  "kitty|Kitty|official"
  "foot|Foot|official"
  "alacritty|Alacritty|official"
  "wezterm|WezTerm|official"
)

SWAPPABLE_MULTIPLEXER_DEFAULT="zellij"
SWAPPABLE_MULTIPLEXER_DEFAULT_TYPE="official"
SWAPPABLE_MULTIPLEXER=(
  "zellij|Zellij|official"
  "tmux|tmux|official"
  "none|None (remove current)|none"
)

# =============================================================================
# ADDONS — optional installs managed by cloudyy-config
# =============================================================================

ADDON_OFFICIAL_OBS=("obs-studio")
ADDON_AUR_OBS=("gpu-screen-recorder")

ADDON_OFFICIAL_GAMING=(
  "steam" "gamemode" "lib32-gamemode"
  "mangohud" "lib32-mangohud" "lutris"
)
ADDON_AUR_GAMING=("protonup-qt" "heroic-games-launcher-bin")

ADDON_OFFICIAL_OFFICE=("libreoffice-still")
ADDON_AUR_OFFICE=()

ADDON_OFFICIAL_DEV=(
  "cmake" "meson" "ninja" "mold" "clang"
  "shellcheck" "shfmt" "stylua" "uv"
  "linux-headers" "dkms" "github-cli" "wev"
)
ADDON_AUR_DEV=("rust-analyzer" "zed" "vscodium" "visual-studio-code-bin")

# =============================================================================
# GPU DRIVERS — selected at runtime by lspci detection
# =============================================================================

OFFICIAL_GPU_NVIDIA=(
  "nvidia-open-dkms" "nvidia-utils" "lib32-nvidia-utils"
  "nvidia-settings" "egl-wayland"
)
AUR_GPU_NVIDIA=()

OFFICIAL_GPU_INTEL=(
  "mesa" "lib32-mesa" "vulkan-intel" "lib32-vulkan-intel"
  "intel-media-driver"
)
AUR_GPU_INTEL=()

OFFICIAL_GPU_AMD=(
  "mesa" "lib32-mesa" "vulkan-radeon" "lib32-vulkan-radeon"
  "libva-mesa-driver" "mesa-vdpau" "lib32-mesa-vdpau"
)
AUR_GPU_AMD=()

# =============================================================================
# ALIASES — for test-install.sh compatibility
# =============================================================================

MINIMAL_GROUP=(
  "${MANDATORY_OFFICIAL_COMPOSITOR[@]}"
  "${MANDATORY_OFFICIAL_DAEMONS[@]}"   "${MANDATORY_AUR_DAEMONS[@]}"
  "${MANDATORY_OFFICIAL_AUDIO[@]}"
  "${MANDATORY_OFFICIAL_INTERFACE[@]}" "${MANDATORY_AUR_INTERFACE[@]}"
  "${MANDATORY_OFFICIAL_SCREENSHOT[@]}"
  "${MANDATORY_OFFICIAL_SHELL[@]}"
  "${MANDATORY_OFFICIAL_SYSTEM[@]}"
  "${MANDATORY_OFFICIAL_THEMING[@]}"   "${MANDATORY_AUR_THEMING[@]}"
  "${MANDATORY_OFFICIAL_MONITORING[@]}"
)

STANDARD_GROUP=(
  "${MINIMAL_GROUP[@]}"
  "${STANDARD_INSTALL_OFFICIAL[@]}"
  "${STANDARD_INSTALL_AUR[@]}"
)
```

- [ ] **Step 3: Verify the file sources cleanly and has no duplicates**

```bash
bash -c '
  source install/dependencies.conf
  echo "MANDATORY_OFFICIAL_COMPOSITOR: ${#MANDATORY_OFFICIAL_COMPOSITOR[@]} pkgs"
  echo "STANDARD_INSTALL_OFFICIAL:     ${#STANDARD_INSTALL_OFFICIAL[@]} pkgs"
  echo "STANDARD_INSTALL_AUR:          ${#STANDARD_INSTALL_AUR[@]} pkgs"
  echo "SWAPPABLE_BROWSER entries:     ${#SWAPPABLE_BROWSER[@]}"
  echo "ADDON_OFFICIAL_GAMING entries: ${#ADDON_OFFICIAL_GAMING[@]}"

  # Check tesseract landed in system array
  printf "%s\n" "${MANDATORY_OFFICIAL_SYSTEM[@]}" | grep -q tesseract \
    && echo "tesseract: OK in MANDATORY_OFFICIAL_SYSTEM" \
    || echo "ERROR: tesseract missing from MANDATORY_OFFICIAL_SYSTEM"

  # Check no CHOICE_ arrays remain
  declare -p CHOICE_TERMINAL 2>/dev/null && echo "ERROR: CHOICE_TERMINAL still exists" || echo "CHOICE_* removed: OK"
'
```

Expected:
```
MANDATORY_OFFICIAL_COMPOSITOR: 9 pkgs
STANDARD_INSTALL_OFFICIAL:     29 pkgs
STANDARD_INSTALL_AUR:          4 pkgs
SWAPPABLE_BROWSER entries:     4
ADDON_OFFICIAL_GAMING entries: 6
tesseract: OK in MANDATORY_OFFICIAL_SYSTEM
CHOICE_* removed: OK
```

- [ ] **Step 4: Commit**

```bash
git add install/dependencies.conf
git commit -m "feat: restructure deps — STANDARD_INSTALL + SWAPPABLE + ADDON arrays"
```

---

## Task 3: Rewrite install/hyprland-install.sh

**Files:**
- Modify: `install/hyprland-install.sh`

Replace the entire file (~809 lines) with the silent version (~200 lines).

- [ ] **Step 1: Write the new hyprland-install.sh**

```bash
#!/usr/bin/env bash
# =============================================================================
# hyprland-install.sh — Silent package installer for cloudyy-linux
# =============================================================================
# Installs all mandatory + standard packages silently.
# GPU drivers auto-detected via lspci — no prompts.
# Run standalone or called from install.sh.
# Safe to source (functions only; main() guarded by BASH_SOURCE check).
# =============================================================================
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPS_FILE="${SCRIPT_DIR}/dependencies.conf"
readonly LIB_FILE="${SCRIPT_DIR}/lib.sh"

[[ ! -f "$LIB_FILE"  ]] && { echo "[✗] lib.sh not found: ${LIB_FILE}" >&2; exit 1; }
[[ ! -f "$DEPS_FILE" ]] && { echo "[✗] dependencies.conf not found: ${DEPS_FILE}" >&2; exit 1; }

source "$LIB_FILE"
source "$DEPS_FILE"

[[ $EUID -eq 0 ]] && { log_error "Do not run as root."; exit 1; }

# =============================================================================
# AUR HELPER
# =============================================================================
setup_aur_helper() {
  log_section "AUR Helper"

  if command -v paru &>/dev/null; then
    AUR_HELPER="paru"; log_ok "Using paru"; return 0
  fi
  if command -v yay &>/dev/null; then
    AUR_HELPER="yay";  log_ok "Using yay";  return 0
  fi

  log "No AUR helper found — installing yay..."
  sudo pacman -S --needed --noconfirm git base-devel

  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '${tmp}'" RETURN
  git clone --depth 1 https://aur.archlinux.org/yay.git "${tmp}/yay"
  (cd "${tmp}/yay" && makepkg -si --noconfirm)

  if command -v yay &>/dev/null; then
    AUR_HELPER="yay"
    log_ok "yay installed."
  else
    log_error "Failed to install yay — AUR packages will be skipped."
  fi
}

# =============================================================================
# GPU DETECTION & LAUNCHER
# =============================================================================

# write_gpu_launcher <vendor>
# Generates ~/.config/hypr/cloudyy-launch.sh with GPU-appropriate env vars.
# Vendor: "nvidia" | "amd" | "intel"
write_gpu_launcher() {
  local vendor="$1"
  local launcher_dir="${HOME}/.config/hypr"
  local launcher="${launcher_dir}/cloudyy-launch.sh"
  local hypr_conf="${HOME}/.config/hypr/hyprland.conf"
  local env_d="${HOME}/.config/environment.d"

  mkdir -p "$launcher_dir" "$env_d"

  cat >"$launcher" <<'HEADER'
#!/usr/bin/env bash
# cloudyy-launch.sh — generated by cloudyy-linux installer
# Sets GPU-appropriate Wayland/EGL environment before handing off to Hyprland.
HEADER

  case "$vendor" in
  nvidia)
    cat >>"$launcher" <<'NVIDIA'
# Resolve DRM card node at launch time (survives reboots with shifting indices)
_drm_node="$(ls /dev/dri/by-path/*-card 2>/dev/null | head -1)"
[[ -n "$_drm_node" ]] && export AQ_DRM_DEVICES="$_drm_node"

export LIBVA_DRIVER_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export WLR_NO_HARDWARE_CURSORS=1
export NVD_BACKEND=direct
# Note: __EGL_VENDOR_LIBRARY_FILENAMES intentionally omitted —
# GLVND expects a JSON vendor config path, not a .so path.
NVIDIA

    cat >"${env_d}/nvidia-wayland.conf" <<'ENVD'
LIBVA_DRIVER_NAME=nvidia
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
NVD_BACKEND=direct
ENVD
    log_ok "NVIDIA environment.d entry written."
    ;;
  amd)
    cat >>"$launcher" <<'AMD'
export LIBVA_DRIVER_NAME=radeonsi
AMD
    ;;
  intel)
    cat >>"$launcher" <<'INTEL'
# iHD for Gen9+ (Broadwell+); i965 for older hardware
if command -v vainfo &>/dev/null; then
  vainfo 2>&1 | grep -q iHD \
    && export LIBVA_DRIVER_NAME=iHD \
    || export LIBVA_DRIVER_NAME=i965
else
  export LIBVA_DRIVER_NAME=iHD
fi
INTEL
    ;;
  esac

  # Universal Wayland block (appended for all vendors)
  cat >>"$launcher" <<'WAYLAND'

export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export SDL_VIDEODRIVER=wayland
export MOZ_ENABLE_WAYLAND=1
export ELECTRON_OZONE_PLATFORM_HINT=auto

exec uwsm start hyprland.desktop
WAYLAND

  chmod +x "$launcher"
  log_ok "GPU launcher written: ${launcher}"

  # Inject env block into hyprland.conf (idempotent)
  if [[ -f "$hypr_conf" ]] && ! grep -q "# cloudyy-gpu-env" "$hypr_conf"; then
    printf '\n# cloudyy-gpu-env\nsource = %s\n' "$launcher" >>"$hypr_conf"
    log_ok "Launcher registered in hyprland.conf."
  else
    log_skip "GPU env block already present in hyprland.conf."
  fi
}

detect_and_install_gpu() {
  log_section "GPU Drivers"

  local gpu_info
  gpu_info="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)"

  if [[ -z "$gpu_info" ]]; then
    log_warn "No GPU detected (VM or unknown hardware) — skipping GPU drivers."
    return 0
  fi

  local has_nvidia=0 has_amd=0 has_intel=0
  echo "$gpu_info" | grep -qi "nvidia"      && has_nvidia=1 || true
  echo "$gpu_info" | grep -qi "amd\|radeon" && has_amd=1   || true
  echo "$gpu_info" | grep -qi "intel"       && has_intel=1  || true

  local primary_vendor=""

  if (( has_nvidia )); then
    log "Detected NVIDIA — installing drivers..."
    pacman_install "NVIDIA" "${OFFICIAL_GPU_NVIDIA[@]}"
    primary_vendor="nvidia"
  fi
  if (( has_amd )); then
    log "Detected AMD — installing drivers..."
    pacman_install "AMD" "${OFFICIAL_GPU_AMD[@]}"
    [[ -z "$primary_vendor" ]] && primary_vendor="amd"
  fi
  if (( has_intel )); then
    log "Detected Intel — installing drivers..."
    pacman_install "Intel" "${OFFICIAL_GPU_INTEL[@]}"
    [[ -z "$primary_vendor" ]] && primary_vendor="intel"
  fi

  [[ -n "$primary_vendor" ]] && write_gpu_launcher "$primary_vendor"
  log_ok "GPU drivers installed."
}

# =============================================================================
# POST-INSTALL CONFIGURATION
# =============================================================================
configure_zram() {
  command -v zram-generator &>/dev/null || return 0
  local conf="/etc/systemd/zram-generator.conf"
  [[ -f "$conf" ]] && { log_skip "ZRAM already configured."; return 0; }
  log "Configuring ZRAM..."
  printf '[zram0]\nzram-size = min(ram / 2, 8192)\ncompression-algorithm = zstd\n' \
    | sudo tee "$conf" >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl start "systemd-zram-setup@zram0.service" 2>/dev/null || true
  log_ok "ZRAM configured."
}

configure_bluetooth() {
  if pacman -Qi bluez &>/dev/null; then
    sudo systemctl enable --now bluetooth.service 2>/dev/null || true
    log_ok "Bluetooth service enabled."
  fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
  log_section "System Update"
  sudo pacman -Syu --noconfirm
  log_ok "System up to date."

  setup_aur_helper
  detect_and_install_gpu

  log_section "Installing — Mandatory Packages"
  pacman_install "Compositor" "${MANDATORY_OFFICIAL_COMPOSITOR[@]}"
  pacman_install "Daemons"    "${MANDATORY_OFFICIAL_DAEMONS[@]}"
  pacman_install "Audio"      "${MANDATORY_OFFICIAL_AUDIO[@]}"
  pacman_install "Interface"  "${MANDATORY_OFFICIAL_INTERFACE[@]}"
  pacman_install "Screenshot" "${MANDATORY_OFFICIAL_SCREENSHOT[@]}"
  pacman_install "Shell"      "${MANDATORY_OFFICIAL_SHELL[@]}"
  pacman_install "System"     "${MANDATORY_OFFICIAL_SYSTEM[@]}"
  pacman_install "Theming"    "${MANDATORY_OFFICIAL_THEMING[@]}"
  pacman_install "Monitoring" "${MANDATORY_OFFICIAL_MONITORING[@]}"
  aur_install    "Daemons"    "${MANDATORY_AUR_DAEMONS[@]}"
  aur_install    "Interface"  "${MANDATORY_AUR_INTERFACE[@]}"
  aur_install    "Theming"    "${MANDATORY_AUR_THEMING[@]}"

  log_section "Installing — Standard Packages"
  pacman_install "Standard" "${STANDARD_INSTALL_OFFICIAL[@]}"
  aur_install    "Standard" "${STANDARD_INSTALL_AUR[@]}"

  configure_zram
  configure_bluetooth

  log_ok "All packages installed."
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
```

- [ ] **Step 2: Verify syntax and lint**

```bash
bash -n install/hyprland-install.sh && echo "syntax OK"
shellcheck install/hyprland-install.sh
```

Expected: no errors (shellcheck may warn about sourced files; those are OK to suppress with `# shellcheck source=install/lib.sh`).

- [ ] **Step 3: Verify the file is safely sourceable (main does not run)**

```bash
bash -c '
  # Mock sudo and pacman so sourcing does not trigger installs
  sudo()   { true; }
  pacman() { true; }
  export -f sudo pacman
  source install/hyprland-install.sh
  echo "sourced OK — main did not run"
'
```

Expected: `sourced OK — main did not run`

- [ ] **Step 4: Commit**

```bash
git add install/hyprland-install.sh
git commit -m "feat: rewrite hyprland-install.sh — silent auto-detect, sources lib.sh"
```

---

## Task 4: Create cloudyy_scripts/cloudyy-config

**Files:**
- Create: `cloudyy_scripts/cloudyy-config`

- [ ] **Step 1: Write cloudyy-config**

```bash
#!/usr/bin/env bash
# =============================================================================
# cloudyy-config — Post-install configuration and package management
# =============================================================================
# Usage:
#   cloudyy-config               Open management menu
#   cloudyy-config --first-run   First-run wizard (called by install.sh)
# =============================================================================
set -euo pipefail

readonly DEPS_FILE="${HOME}/cloudyy-linux/install/dependencies.conf"
readonly LIB_FILE="${HOME}/cloudyy-linux/install/lib.sh"
readonly FIRST_RUN_FLAG="${HOME}/.config/cloudyy/config-done"

if [[ ! -f "$LIB_FILE" ]]; then
  echo "[✗] lib.sh not found at ${LIB_FILE}" >&2
  echo "    Is cloudyy-linux cloned to ~/cloudyy-linux?" >&2
  exit 1
fi
if [[ ! -f "$DEPS_FILE" ]]; then
  echo "[✗] dependencies.conf not found at ${DEPS_FILE}" >&2
  exit 1
fi

source "$LIB_FILE"
source "$DEPS_FILE"

# Detect which AUR helper is available (mirrors hyprland-install.sh logic)
command -v paru &>/dev/null && AUR_HELPER="paru"
command -v yay  &>/dev/null && AUR_HELPER="yay"

# =============================================================================
# HELPERS
# =============================================================================

# detect_current <SWAPPABLE_array_name>
# Prints the name of whichever package in the array is currently installed,
# or "none" if none are found.
detect_current() {
  local arr_name="$1"
  local -n _arr="$arr_name"
  local entry pkg
  for entry in "${_arr[@]}"; do
    pkg="${entry%%|*}"
    [[ "$pkg" == "none" ]] && continue
    if pacman -Qi "$pkg" &>/dev/null; then
      echo "$pkg"
      return 0
    fi
  done
  echo "none"
}

# addon_installed <sentinel-package>
# Returns 0 if the package is installed, 1 otherwise.
addon_installed() {
  pacman -Qi "$1" &>/dev/null
}

# =============================================================================
# SWAP
# =============================================================================

# do_swap <CATEGORY>
# CATEGORY must match a SWAPPABLE_<CATEGORY> array in dependencies.conf.
do_swap() {
  local category="$1"
  local arr_name="SWAPPABLE_${category}"
  local -n arr="$arr_name"

  local current
  current="$(detect_current "$arr_name")"

  printf '\n%s  Swap %s%s\n' "$BOLD" "${category,,}" "$RESET"
  divider

  local i=1 entry pkg label pkg_type
  for entry in "${arr[@]}"; do
    pkg="${entry%%|*}"
    label="${entry#*|}"; label="${label%%|*}"
    local marker=""
    [[ "$pkg" == "$current" ]] && marker="  ${DIM}← current${RESET}"
    printf '  %s%d)%s %s%b\n' "$CYAN" "$i" "$RESET" "$label" "$marker"
    (( i++ ))
  done
  printf '  %sq)%s Back\n\n' "$CYAN" "$RESET"

  local sel
  read -rp "  Selection: " sel
  [[ "${sel,,}" == "q" || -z "$sel" ]] && return 0

  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#arr[@]} )); then
    local chosen="${arr[$((sel - 1))]}"
    pkg="${chosen%%|*}"
    pkg_type="${chosen##*|}"

    if [[ "$pkg" == "$current" ]]; then
      log_warn "$(printf '%s is already installed.' "$pkg")"
      return 0
    fi

    if [[ "$pkg" == "none" ]]; then
      if [[ "$current" != "none" ]]; then
        log "Removing ${current}..."
        yay -Rns --noconfirm "$current" 2>/dev/null || \
          sudo pacman -Rns --noconfirm "$current" 2>/dev/null || true
        log_ok "Removed ${current}."
      fi
      return 0
    fi

    # Remove current
    if [[ "$current" != "none" ]]; then
      log "Removing ${current}..."
      yay -Rns --noconfirm "$current" 2>/dev/null || \
        sudo pacman -Rns --noconfirm "$current" 2>/dev/null || true
    fi

    # Install new
    if [[ "$pkg_type" == "official" ]]; then
      pacman_install "$category" "$pkg"
    else
      aur_install "$category" "$pkg"
    fi
  else
    log_warn "Invalid selection."
  fi
}

# =============================================================================
# ADD-ONS
# =============================================================================

# toggle_addon <sentinel-pkg> <OFFICIAL_array_name> <AUR_array_name>
toggle_addon() {
  local sentinel="$1"
  local official_arr="$2"
  local aur_arr="$3"
  local -n _official="$official_arr"
  local -n _aur="$aur_arr"

  if addon_installed "$sentinel"; then
    log "Removing addon..."
    local all_pkgs=("${_official[@]}" "${_aur[@]}")
    yay -Rns --noconfirm "${all_pkgs[@]}" 2>/dev/null || true
    log_ok "Removed."
  else
    log "Installing addon..."
    (( ${#_official[@]} > 0 )) && pacman_install "Addon" "${_official[@]}"
    (( ${#_aur[@]} > 0 ))      && aur_install    "Addon" "${_aur[@]}"
    log_ok "Installed."
  fi
}

manage_addons() {
  while true; do
    local obs_icon gaming_icon office_icon dev_icon
    addon_installed "obs-studio"       && obs_icon="✓"     || obs_icon=" "
    addon_installed "steam"            && gaming_icon="✓"  || gaming_icon=" "
    addon_installed "libreoffice-still" && office_icon="✓" || office_icon=" "
    addon_installed "cmake"            && dev_icon="✓"     || dev_icon=" "

    printf '\n%s  Add-ons%s\n' "$BOLD" "$RESET"
    divider
    printf '  1) [%s] OBS + Screen Recording\n'          "$obs_icon"
    printf '  2) [%s] Gaming (Steam, Lutris, MangoHud)\n' "$gaming_icon"
    printf '  3) [%s] Office (LibreOffice)\n'             "$office_icon"
    printf '  4) [%s] Dev Tools (cmake, clang, uv...)\n' "$dev_icon"
    printf '  q) Back\n\n'

    local sel
    read -rp "  Toggle [1-4, q]: " sel
    case "$sel" in
      1) toggle_addon "obs-studio"        ADDON_OFFICIAL_OBS     ADDON_AUR_OBS     ;;
      2) toggle_addon "steam"             ADDON_OFFICIAL_GAMING  ADDON_AUR_GAMING  ;;
      3) toggle_addon "libreoffice-still" ADDON_OFFICIAL_OFFICE  ADDON_AUR_OFFICE  ;;
      4) toggle_addon "cmake"             ADDON_OFFICIAL_DEV     ADDON_AUR_DEV     ;;
      q|Q) return 0 ;;
      *) log_warn "Enter 1–4 or q." ;;
    esac
  done
}

# =============================================================================
# MENUS
# =============================================================================

main_menu() {
  while true; do
    local browser terminal multiplexer
    browser="$(detect_current SWAPPABLE_BROWSER)"
    terminal="$(detect_current SWAPPABLE_TERMINAL)"
    multiplexer="$(detect_current SWAPPABLE_MULTIPLEXER)"

    printf '\n'
    printf '%s╔══════════════════════════════════════╗%s\n' "$BOLD" "$RESET"
    printf '%s║         cloudyy-config               ║%s\n' "$BOLD" "$RESET"
    printf '%s╚══════════════════════════════════════╝%s\n' "$BOLD" "$RESET"
    printf '\n'
    printf '  1) Swap browser      %s(%s)%s\n' "$DIM" "$browser"    "$RESET"
    printf '  2) Swap terminal     %s(%s)%s\n' "$DIM" "$terminal"   "$RESET"
    printf '  3) Swap multiplexer  %s(%s)%s\n' "$DIM" "$multiplexer" "$RESET"
    printf '  4) Manage add-ons\n'
    printf '  5) Exit\n\n'

    local sel
    read -rp "  Choice: " sel
    case "$sel" in
      1) do_swap "BROWSER"     ;;
      2) do_swap "TERMINAL"    ;;
      3) do_swap "MULTIPLEXER" ;;
      4) manage_addons         ;;
      5|q|Q) exit 0            ;;
      *) log_warn "Enter 1–5." ;;
    esac
  done
}

first_run() {
  [[ -f "$FIRST_RUN_FLAG" ]] && { main_menu; return 0; }

  printf '\n%s╔══════════════════════════════════════════╗%s\n' "$BOLD" "$RESET"
  printf '%s║   cloudyy-linux is ready!               ║%s\n' "$BOLD" "$RESET"
  printf '%s╚══════════════════════════════════════════╝%s\n\n' "$BOLD" "$RESET"
  printf 'Your system is installed with the default cloudyy package set.\n'
  printf 'Want to swap anything before you log in?\n\n'

  local resp
  read -rp "  Customise now? [y/N]: " resp
  if [[ "${resp,,}" =~ ^y ]]; then
    main_menu
  fi

  mkdir -p "$(dirname "$FIRST_RUN_FLAG")"
  touch "$FIRST_RUN_FLAG"

  printf '\n%sRun%s cloudyy-config %sanytime to customise your setup.%s\n\n' \
    "$BOLD" "$RESET" "$DIM" "$RESET"
}

# =============================================================================
# ENTRY POINT
# =============================================================================
if [[ "${1:-}" == "--first-run" ]]; then
  first_run
else
  main_menu
fi
```

- [ ] **Step 2: Make executable and verify syntax**

```bash
chmod +x cloudyy_scripts/cloudyy-config
bash -n cloudyy_scripts/cloudyy-config && echo "syntax OK"
shellcheck cloudyy_scripts/cloudyy-config
```

Expected: no errors.

- [ ] **Step 3: Verify it sources dependencies correctly without executing**

```bash
bash -c '
  # Stub pacman so detect_current does not error on a machine without the AUR packages
  pacman() { return 1; }
  export -f pacman
  # Run with a fake arg so it hits the entry-point guard but not first_run/main_menu
  bash cloudyy_scripts/cloudyy-config --dry-check 2>/dev/null || true
  echo "sourced and exited cleanly"
'
```

Expected: `sourced and exited cleanly` (the script exits because `--dry-check` hits the else branch which calls `main_menu`, which calls `read` — the pipe closes and it exits non-zero, which is fine for this check; if you want a cleaner test, use `echo 5 | bash cloudyy_scripts/cloudyy-config` and expect it to exit after choosing "Exit").

Better smoke test:

```bash
echo "5" | bash cloudyy_scripts/cloudyy-config 2>/dev/null; echo "exit: $?"
```

Expected: `exit: 0` (user selected "5 = Exit").

- [ ] **Step 4: Commit**

```bash
git add cloudyy_scripts/cloudyy-config
git commit -m "feat: add cloudyy-config — re-runnable swap/addon management tool"
```

---

## Task 5: Update install/install.sh

**Files:**
- Modify: `install/install.sh`

Two changes: (1) parse `--unattended` flag, (2) call `cloudyy-config --first-run` at end of `phase_finalize`.

- [ ] **Step 1: Add --unattended to the argument parser**

In `install/install.sh`, find the `main()` argument case block (around line 233):

```bash
  case "${1:-}" in
  --help | -h)
    ...
  --reset)
    ...
  --dry-run | -d)
    ...
  "") ;;
  *)
    printf '%sUnknown option: %s%s\n' "$RED" "$1" "$RESET" >&2
```

Replace the `"") ;;` and `*)` lines with:

```bash
  --unattended | -u)
    UNATTENDED=1
    ;;
  "") ;;
  *)
    printf '%sUnknown option: %s%s\n' "$RED" "$1" "$RESET" >&2
```

Also add the variable declaration near the top of `main()`, before the case block:

```bash
  local UNATTENDED=0
```

And update the usage comment at the top of the file (lines 6–9) to include:

```bash
#   ./install.sh --unattended  Silent install — skip post-install config prompt
```

- [ ] **Step 2: Call cloudyy-config --first-run in phase_finalize**

Find `phase_finalize()` (around line 194). Replace:

```bash
phase_finalize() {
  printf '\n%s%s════════════════════════════════════════════%s\n' "$BOLD" "$GREEN" "$RESET"
  printf '%s  🎉  cloudyy-linux installation complete!  %s\n' "$BOLD" "$RESET"
  printf '%s%s════════════════════════════════════════════%s\n\n' "$BOLD" "$GREEN" "$RESET"
  printf 'Log saved to:\n  %s%s%s\n\n' "$CYAN" "$LOG_FILE" "$RESET"
  printf '%sNext steps:%s\n' "$YELLOW" "$RESET"
  printf '  1. Log out of your current session\n'
  printf '  2. Select Hyprland at your display manager, or run: %sHyprland%s\n' "$BOLD" "$RESET"
  printf '  3. Run %s./install.sh --reset%s if you ever want to reinstall from scratch\n\n' "$BOLD" "$RESET"
}
```

With:

```bash
phase_finalize() {
  printf '\n%s%s════════════════════════════════════════════%s\n' "$BOLD" "$GREEN" "$RESET"
  printf '%s  🎉  cloudyy-linux installation complete!  %s\n' "$BOLD" "$RESET"
  printf '%s%s════════════════════════════════════════════%s\n\n' "$BOLD" "$GREEN" "$RESET"
  printf 'Log saved to:\n  %s%s%s\n\n' "$CYAN" "$LOG_FILE" "$RESET"

  local config_script="${HOME}/cloudyy_scripts/cloudyy-config"
  if [[ "${UNATTENDED:-0}" != "1" ]] && [[ -x "$config_script" ]]; then
    "$config_script" --first-run
  fi

  printf '%sNext steps:%s\n' "$YELLOW" "$RESET"
  printf '  1. Log out of your current session\n'
  printf '  2. Select Hyprland at your display manager, or run: %sHyprland%s\n' "$BOLD" "$RESET"
  printf '  3. Run %s./install.sh --reset%s if you ever want to reinstall from scratch\n\n' "$BOLD" "$RESET"
}
```

- [ ] **Step 3: Make UNATTENDED visible to phase_finalize**

`UNATTENDED` is declared as `local` inside `main()`, so `phase_finalize` (called from `main`) can't see it. Change it from a local to a script-level variable. Add this near the top of the file, after the constants block (around line 21):

```bash
UNATTENDED=0
```

Remove the `local UNATTENDED=0` line added to `main()` in Step 1, and change the assignment in the case block to:

```bash
  --unattended | -u)
    UNATTENDED=1
    ;;
```

- [ ] **Step 4: Verify syntax**

```bash
bash -n install/install.sh && echo "syntax OK"
shellcheck install/install.sh
```

Expected: no errors.

- [ ] **Step 5: Smoke-test --unattended flag parsing**

```bash
bash -c '
  # Source only the argument-parsing logic
  UNATTENDED=0
  arg="${1:-}"
  case "$arg" in
    --unattended|-u) UNATTENDED=1 ;;
  esac
  echo "UNATTENDED=$UNATTENDED"
' -- --unattended
```

Expected: `UNATTENDED=1`

```bash
bash -c '
  UNATTENDED=0
  arg="${1:-}"
  case "$arg" in
    --unattended|-u) UNATTENDED=1 ;;
  esac
  echo "UNATTENDED=$UNATTENDED"
' --
```

Expected: `UNATTENDED=0`

- [ ] **Step 6: Commit**

```bash
git add install/install.sh
git commit -m "feat: install.sh --unattended flag + cloudyy-config first-run call"
```

---

## Self-Review Checklist

- [x] **lib.sh extracted** — Task 1 creates it with all shared functions; double-source guard included
- [x] **hyprland-install.sh sources lib.sh** — Task 3 starts with `source "$LIB_FILE"`
- [x] **BASH_SOURCE guard** — Task 3 ends with `[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"`
- [x] **tesseract in mandatory** — Task 2 Step 1 adds it to `MANDATORY_OFFICIAL_SYSTEM`
- [x] **CHOICE_*/OPTIONAL_* removed** — Task 2 Step 2 replaces them entirely
- [x] **STANDARD_INSTALL arrays** — Defined in Task 2, consumed in Task 3 main()
- [x] **SWAPPABLE_* arrays** — Defined in Task 2, consumed by `do_swap()` in Task 4
- [x] **ADDON_* arrays** — Defined in Task 2, consumed by `toggle_addon()` in Task 4
- [x] **GPU auto-detect (no menu)** — `detect_and_install_gpu()` in Task 3 uses lspci only
- [x] **AUR helper silent install** — `setup_aur_helper()` in Task 3 installs yay with no prompt
- [x] **cloudyy-config --first-run** — Task 4 implements it; Task 5 wires it into install.sh
- [x] **--unattended skips cloudyy-config** — Task 5 guards the call with `[[ "${UNATTENDED:-0}" != "1" ]]`
- [x] **cloudyy-config re-runnable** — `main_menu()` in Task 4 is a persistent loop
- [x] **First-run flag** — `FIRST_RUN_FLAG` written after first-run completes; subsequent invocations with `--first-run` go straight to `main_menu`
- [x] **All commits to dev branch** — instructions reference `dev` branch throughout
