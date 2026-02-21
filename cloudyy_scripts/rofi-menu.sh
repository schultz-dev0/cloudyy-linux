#!/usr/bin/env bash
# ==============================================================================
# HYPRLAND DASHBOARD (ROFI FRONTEND)
# ==============================================================================
# Dependencies: rofi, uwsm, kitty, ImageMagick/magick
# ==============================================================================

set -uo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================

readonly THEME_CTL="${HOME}/cloudyy_scripts/theme_controller.sh"
readonly HKBM_CMD="${HOME}/cloudyy_scripts/cloudyy-other/hkbm"
readonly HCM_CMD="${HOME}/cloudyy_scripts/cloudyy-other/hcm"
readonly BASE_WALL_DIR="${HOME}/Wallpapers"
readonly CACHE_DIR="${HOME}/.cache/rofi_thumbs"
readonly TEMP_INPUT="/tmp/rofi_input_$$"

readonly THUMB_SIZE=250
readonly MAX_JOBS=$(nproc)

readonly ROFI_CMD=(rofi -dmenu -i)
readonly SUPPORTED_FORMATS=("*.jpg" "*.jpeg" "*.png" "*.webp")

trap 'rm -f "$TEMP_INPUT"' EXIT INT TERM

# ==============================================================================
# MODE DETECTION
# ==============================================================================

get_current_mode() {
  local raw_mode
  raw_mode=$("$THEME_CTL" get-mode 2>/dev/null || echo "dark")
  raw_mode=$(echo "$raw_mode" | tr -d '[:space:]')

  [[ "$raw_mode" != "light" && "$raw_mode" != "dark" ]] && raw_mode="dark"
  echo "$raw_mode"
}

CURRENT_MODE=$(get_current_mode)
DISPLAY_MODE="$(tr '[:lower:]' '[:upper:]' <<<${CURRENT_MODE:0:1})${CURRENT_MODE:1}"
WALL_DIR="$BASE_WALL_DIR/$DISPLAY_MODE"
[[ ! -d "$WALL_DIR" ]] && WALL_DIR="$BASE_WALL_DIR"

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

init_dirs() {
  mkdir -p "$CACHE_DIR" "$WALL_DIR"
}

menu() {
  local prompt="$1"
  local options="$2"
  local extra_args=("${@:3}")
  printf "%b" "$options" | "${ROFI_CMD[@]}" -p "$prompt" "${extra_args[@]}"
}

centered_menu() {
  local prompt="$1"
  local options="$2"
  printf "%b" "$options" | rofi -dmenu -i -p "$prompt" \
    -theme-str 'window { location: center; anchor: center; width: 450px; }' \
    -theme-str 'listview { lines: 8; }' \
    -theme-str 'element { padding: 12px; }' \
    -theme-str 'element-text { font: "JetBrainsMono Nerd Font 12"; }'
}

run_app() {
  nohup uwsm-app -- "$@" >/dev/null 2>&1 &
  disown
}

gen_thumb() {
  local img="$1"
  local thumb="$CACHE_DIR/$(basename "$img").png"
  [[ -f "$thumb" ]] && return 0

  local converter="convert"
  command -v magick &>/dev/null && converter="magick"

  "$converter" "${img}[0]" -strip \
    -resize "${THUMB_SIZE}x${THUMB_SIZE}^" \
    -gravity center \
    -extent "${THUMB_SIZE}x${THUMB_SIZE}" \
    -quality 85 "$thumb" 2>/dev/null || return 1
}
export -f gen_thumb
export CACHE_DIR THUMB_SIZE

# ==============================================================================
# APPEARANCE MENU (INTEGRATED THEME OPTIONS)
# ==============================================================================

show_appearance_menu() {
  # Refresh current mode
  CURRENT_MODE=$(get_current_mode)
  DISPLAY_MODE="$(tr '[:lower:]' '[:upper:]' <<<${CURRENT_MODE:0:1})${CURRENT_MODE:1}"

  local choice
  choice=$(menu "Theme: $DISPLAY_MODE" \
    "󰔎 Toggle Mode\n󰸉 Select Wallpaper\n \n󰑕 Next Wallpaper\n󰗆 Random Wallpaper\n󰜉 Refresh Colors\n󰘍 Back")

  case "${choice}" in
  *"Toggle Mode"*)
    run_app "$THEME_CTL" toggle
    notify-send "Theme" "Switching theme mode..." -t 2000
    ;;
  *"Select Wallpaper"*)
    select_wallpaper
    ;;
  *"Next Wallpaper"*)
    run_app "$THEME_CTL" next
    notify-send "Theme" "Loading next wallpaper..." -t 2000
    ;;
  *"Random Wallpaper"*)
    run_app "$THEME_CTL" random
    notify-send "Theme" "Applying random wallpaper..." -t 2000
    ;;
  *"Refresh Colors"*)
    run_app "$THEME_CTL" refresh
    notify-send "Theme" "Refreshing colors..." -t 2000
    ;;
  *"Back"*)
    show_main_menu
    ;;
  *)
    exit 0
    ;;
  esac
}

# ==============================================================================
# WALLPAPER SELECTOR
# ==============================================================================

select_wallpaper() {
  [[ ! -d "$WALL_DIR" ]] || [[ ! -r "$WALL_DIR" ]] && {
    notify-send "Error" "Cannot access: $WALL_DIR"
    return 1
  }

  # Generate thumbnails in parallel
  find -L "$WALL_DIR" -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0 2>/dev/null |
    xargs -0 -P "$MAX_JOBS" -I {} bash -c 'gen_thumb "$@"' _ {}

  # Map basename -> full path
  declare -A wallpaper_paths

  # Clear temp input
  >"$TEMP_INPUT"

  # Build rofi input with thumbnails
  while IFS= read -r -d '' img; do
    local basename_img="$(basename "$img")"
    local thumb="$CACHE_DIR/${basename_img}.png"

    if [[ -f "$thumb" ]]; then
      echo -en "${basename_img}\0icon\x1f$thumb\n" >>"$TEMP_INPUT"
      wallpaper_paths["$basename_img"]="$img"
    fi
  done < <(find -L "$WALL_DIR" -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0 2>/dev/null | sort -z)

  [[ ! -s "$TEMP_INPUT" ]] && {
    notify-send "No Wallpapers" "No images found in $WALL_DIR"
    return 1
  }

  # Show wallpaper selector
  local selection
  selection=$(rofi -dmenu -i -p "Select Wallpaper" \
    -theme-str 'window { width: 60%; }' \
    -theme-str 'listview { columns: 4; lines: 3; flow: horizontal; }' \
    -theme-str 'element { orientation: vertical; padding: 20px; spacing: 10px; }' \
    -theme-str 'element-icon { size: 150px; horizontal-align: 0.5; }' \
    -theme-str 'element-text { horizontal-align: 0.5; }' \
    -show-icons <"$TEMP_INPUT")

  # Apply selected wallpaper
  if [[ -n "$selection" ]] && [[ -n "${wallpaper_paths[$selection]}" ]]; then
    run_app "$THEME_CTL" set-image "${wallpaper_paths[$selection]}"
  elif [[ -n "$selection" ]]; then
    notify-send "Error" "Could not find path for: $selection"
    return 1
  fi
}

# ==============================================================================
# KEYBINDS MENU
# ==============================================================================

show_keybinds_menu() {
  if [[ ! -x "$HKBM_CMD" ]]; then
    notify-send "Error" "hkbm not found at: $HKBM_CMD"
    return
  fi

  nohup kitty --title "Keybind Manager" -e "$HKBM_CMD" >/dev/null 2>&1 &
}

# ==============================================================================
# FONT SELECTION MENU
# ==============================================================================

show_font_menu() {
  rofi -show fontmenu -modi "fontmenu:~/cloudyy_scripts/font-selector.sh"
}

# ==============================================================================
# PACKAGE MANAGER MENU
# ==============================================================================

show_package_menu() {
  local choice
  choice=$(menu "Package Manager" \
    "󰆴 Remove Package\n󰈙 List Installed\n󰋼 Package Info\n󰸉 Back")

  case "${choice}" in
  *"Remove Package"*)
    remove_package
    ;;
  *"List Installed"*)
    list_packages
    ;;
  *"Package Info"*)
    package_info
    ;;
  *"Back"*)
    show_main_menu
    ;;
  *)
    exit 0
    ;;
  esac
}

remove_package() {
  # Core packages that should never be removed
  local -a protected_packages=(
    "base"
    "base-devel"
    "linux"
    "linux-headers"
    "linux-firmware"
    "systemd"
    "bash"
    "glibc"
    "pacman"
    "sudo"
    "hyprland"
    "rofi"
    "kitty"
    "networkmanager"
    "grub"
    "efibootmgr"
    "mesa"
    "xorg-server"
    "wayland"
  )

  # Detect package manager
  local pkg_manager=""
  if command -v yay &>/dev/null; then
    pkg_manager="yay"
  elif command -v paru &>/dev/null; then
    pkg_manager="paru"
  elif command -v pacman &>/dev/null; then
    pkg_manager="pacman"
  else
    notify-send "Error" "No supported package manager found"
    return 1
  fi

  # Get list of explicitly installed packages
  local pkg_list
  if [[ "$pkg_manager" == "pacman" ]]; then
    pkg_list=$(pacman -Qe | awk '{print $1}')
  else
    pkg_list=$($pkg_manager -Qe | awk '{print $1}')
  fi

  # Filter out protected packages
  local filtered_list=""
  while IFS= read -r pkg; do
    local is_protected=0
    for protected in "${protected_packages[@]}"; do
      [[ "$pkg" == "$protected" ]] && is_protected=1 && break
    done
    [[ $is_protected -eq 0 ]] && filtered_list+="$pkg\n"
  done <<<"$pkg_list"

  # Show package selection
  local selected_pkg
  selected_pkg=$(echo -e "$filtered_list" | rofi -dmenu -i -p "Select package to remove" \
    -theme-str 'window { width: 50%; }' \
    -theme-str 'listview { lines: 15; }' \
    -mesg "$(echo "$pkg_list" | wc -l) packages installed | Protected: ${#protected_packages[@]}")

  [[ -z "$selected_pkg" ]] && return 0

  # Confirmation
  local confirm
  confirm=$(centered_menu "Remove $selected_pkg?" \
    "󰆴 Confirm Removal\n󰸉 Cancel")
  # ==============================================================================
  # KEYBINDS MENU
  # ==============================================================================
  case "${confirm}" in
  *"Confirm"*)
    if [[ "$pkg_manager" == "pacman" ]]; then
      kitty -e sh -c "sudo pacman -Rns $selected_pkg; read -p 'Press Enter to close'" &
    else
      kitty -e sh -c "$pkg_manager -Rns $selected_pkg; read -p 'Press Enter to close'" &
    fi
    ;;
  *)
    show_package_menu
    ;;
  esac
}

list_packages() {
  local pkg_manager=""
  if command -v yay &>/dev/null; then
    pkg_manager="yay"
  elif command -v paru &>/dev/null; then
    pkg_manager="paru"
  elif command -v pacman &>/dev/null; then
    pkg_manager="pacman"
  else
    notify-send "Error" "No supported package manager found"
    return 1
  fi

  if command -v kitty &>/dev/null; then
    if [[ "$pkg_manager" == "pacman" ]]; then
      kitty -e sh -c "pacman -Q | less; read -p 'Press Enter to close'" &
    else
      kitty -e sh -c "$pkg_manager -Q | less; read -p 'Press Enter to close'" &
    fi
  fi
}

package_info() {
  local pkg_manager=""
  if command -v yay &>/dev/null; then
    pkg_manager="yay"
  elif command -v paru &>/dev/null; then
    pkg_manager="paru"
  elif command -v pacman &>/dev/null; then
    pkg_manager="pacman"
  else
    notify-send "Error" "No supported package manager found"
    return 1
  fi

  local pkg_list
  if [[ "$pkg_manager" == "pacman" ]]; then
    pkg_list=$(pacman -Q | awk '{print $1}')
  else
    pkg_list=$($pkg_manager -Q | awk '{print $1}')
  fi

  local selected_pkg
  selected_pkg=$(echo "$pkg_list" | rofi -dmenu -i -p "Select package for info" \
    -theme-str 'window { width: 50%; }' \
    -theme-str 'listview { lines: 15; }')

  [[ -z "$selected_pkg" ]] && return 0

  if command -v kitty &>/dev/null; then
    if [[ "$pkg_manager" == "pacman" ]]; then
      kitty -e sh -c "pacman -Qi $selected_pkg; read -p 'Press Enter to close'" &
    else
      kitty -e sh -c "$pkg_manager -Qi $selected_pkg; read -p 'Press Enter to close'" &
    fi
  fi
}

# ==============================================================================
# SYSTEM MENU
# ==============================================================================

show_system_menu() {
  local uptime kernel
  uptime=$(uptime -p | sed 's/up //' || echo "Unknown")
  kernel=$(uname -r || echo "Unknown")

  local choice
  choice=$(menu "System" \
    "󰢮 System Info\n󰑐 Refresh\n󰿅 Process Killer\n󰘍 Back" \
    -mesg "Uptime: $uptime | Kernel: $kernel")

  case "${choice,,}" in
  *info*)
    command -v kitty &>/dev/null &&
      kitty -e sh -c "fastfetch 2>/dev/null || neofetch 2>/dev/null || echo 'No system info tool'; read -p 'Press Enter...'" &
    ;;
  *refresh*)
    show_system_menu
    ;;
  *killer*)
    command -v kitty &>/dev/null &&
      kitty -e sh -c "hyprctl kill; read -p 'Click on window to close'" &
    ;;
  *back*)
    show_main_menu
    ;;
  *)
    exit 0
    ;;
  esac
}

# ==============================================================================
# POWER MENU
# ==============================================================================

show_power_menu() {
  exec ~/cloudyy_scripts/power-menu.sh
}
# ==============================================================================
# CONFIGURATION MENU
# ==============================================================================

configuration_menu() {
  if [[ ! -x "$HCM_CMD" ]]; then
    notify-send "Error" "hcm not found at: $HCM_CMD"
    return
  fi

  nohup kitty --title "Config manager" -e "$HCM_CMD" >/dev/null 2>&1 &
}

# ==============================================================================
# APPLICATIONS MENU
# ==============================================================================

show_applications_menu() {
  rofi -show drun \
    -theme-str 'listview { columns: 4; lines: 6; }' \
    -theme-str 'element { orientation: vertical; children: [ element-icon, element-text ]; padding: 10px; }' \
    -theme-str 'element-icon { size: 64px; horizontal-align: 0.5; }' \
    -theme-str 'element-text { horizontal-align: 0.5; }' \
    -show-icons
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

show_main_menu() {
  local choice
  choice=$(menu "Dashboard" \
    "󱓻 Appearance\n󰀻 Applications\n Fonts\n󱊨 Keybinds\n󰹑 System\n⏻ Configuration\n󰏖 Packages\n󰐥 Power")

  case "$choice" in
  "󱓻 Appearance")
    show_appearance_menu
    ;;
  "󰀻 Applications")
    show_applications_menu
    ;;
  " Fonts")
    show_font_menu
    ;;
  "󱊨 Keybinds")
    show_keybinds_menu
    ;;
  "󰹑 System")
    show_system_menu
    ;;
  "⏻ Configuration")
    configuration_menu
    ;;
  "󰏖 Packages")
    show_package_menu
    ;;
  "󰐥 Power")
    show_power_menu
    ;;
  *)
    exit 0
    ;;
  esac
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

main() {
  # Verify dependencies
  command -v rofi &>/dev/null || {
    notify-send "Error" "rofi is not installed"
    exit 1
  }

  [[ ! -x "$THEME_CTL" ]] && {
    notify-send "Error" "Theme controller not found: $THEME_CTL"
    exit 1
  }

  init_dirs

  # Handle command-line arguments
  if [[ -n "${1:-}" ]]; then
    case "$1" in
    --random)
      run_app "$THEME_CTL" random
      ;;
    --next)
      run_app "$THEME_CTL" next
      ;;
    --toggle)
      run_app "$THEME_CTL" toggle
      ;;
    --select)
      select_wallpaper
      ;;
    --appearance)
      show_appearance_menu
      ;;
    --applications)
      show_applications_menu
      ;;
    --packages)
      show_package_menu
      ;;
    *)
      show_main_menu
      ;;
    esac
  else
    show_main_menu
  fi
}

main "$@"
