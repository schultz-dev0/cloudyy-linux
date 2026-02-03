#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# HYPRLAND DASHBOARD (ROFI FRONTEND) - Updated with Full Theme Integration
# Optimized for Bash 5+ | Dependencies: rofi, uwsm, kitty, ImageMagick/magick
# -----------------------------------------------------------------------------

set -uo pipefail

# --- CONFIGURATION ---
readonly THEME_CTL="${HOME}/cloudyy_scripts/theme_controller.sh"
readonly BASE_WALL_DIR="${HOME}/Wallpapers"
readonly CACHE_DIR="${HOME}/.cache/rofi_thumbs"
readonly TEMP_INPUT="/tmp/rofi_input_$$"

readonly THUMB_SIZE=250
readonly MAX_JOBS=$(nproc)

readonly ROFI_CMD=(
  rofi
  -dmenu
  -i
)

readonly SUPPORTED_FORMATS=("*.jpg" "*.jpeg" "*.png" "*.webp")

trap 'rm -f "$TEMP_INPUT"' EXIT INT TERM

# --- MODE DETECTION ---
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

# --- CORE FUNCTIONS ---

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

build_find_cmd() {
  local dir="$1"
  local cmd="find \"$dir\" -type f \\("

  for i in "${!SUPPORTED_FORMATS[@]}"; do
    [[ $i -gt 0 ]] && cmd+=" -o"
    cmd+=" -iname \"${SUPPORTED_FORMATS[$i]}\""
  done

  cmd+=" \\)"
  echo "$cmd"
}

# --- THEME TOGGLE MENU (EXPANDED) ---

show_theme_toggle_menu() {
  # Refresh current mode
  CURRENT_MODE=$(get_current_mode)
  DISPLAY_MODE="$(tr '[:lower:]' '[:upper:]' <<<${CURRENT_MODE:0:1})${CURRENT_MODE:1}"

  local light_indicator=""
  local dark_indicator=""

  [[ "$CURRENT_MODE" == "light" ]] && light_indicator=" ✓" || dark_indicator=" ✓"

  local choice
  choice=$(centered_menu "Theme: $DISPLAY_MODE" \
    "󰖨 Light Mode$light_indicator\n󰖔 Dark Mode$dark_indicator\n󰆥 Toggle Mode\n \n󰑐 Next Wallpaper\n󰗆 Random Wallpaper\n󰘁 Refresh Colors\n󰁯 Reset Theme\n󰸉 Back")

  case "${choice}" in
  *"Light Mode"*)
    if [[ "$CURRENT_MODE" != "light" ]]; then
      run_app "$THEME_CTL" --force set --mode light
      notify-send "Theme" "Switching to Light mode..." -t 2000
    fi
    ;;
  *"Dark Mode"*)
    if [[ "$CURRENT_MODE" != "dark" ]]; then
      run_app "$THEME_CTL" --force set --mode dark
      notify-send "Theme" "Switching to Dark mode..." -t 2000
    fi
    ;;
  *"Toggle Mode"*)
    run_app "$THEME_CTL" --force toggle
    notify-send "Theme" "Toggling theme..." -t 2000
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
  *"Reset Theme"*)
    # Confirmation submenu
    local confirm
    confirm=$(centered_menu "Reset Theme?" \
      "󰁯 Reset & Apply Wallpaper\n󰁯 Reset Only (No Wallpaper)\n󰸉 Cancel")

    case "${confirm}" in
    *"Reset & Apply"*)
      run_app "$THEME_CTL" --force reset --apply
      notify-send "Theme" "Theme reset, applying wallpaper..." -t 3000
      ;;
    *"Reset Only"*)
      run_app "$THEME_CTL" --force reset
      notify-send "Theme" "Theme state reset to dark mode" -t 3000
      ;;
    *)
      show_theme_toggle_menu
      ;;
    esac
    ;;
  *"Back"*)
    show_appearance_menu
    ;;
  *)
    exit 0
    ;;
  esac
}

# --- APPEARANCE MENU ---

show_appearance_menu() {
  local choice
  choice=$(menu "Theme: $DISPLAY_MODE" \
    "󰔎 Theme Mode\n󰸉 Select Wallpaper\n󰘁 Diagnostics\n󰸉 Back")

  case "${choice}" in
  *"Theme Mode"*)
    show_theme_toggle_menu
    ;;
  *"Select Wallpaper"*)
    select_wallpaper
    ;;
  *"Diagnostics"*)
    show_diagnostics_menu
    ;;
  *"Back"*)
    show_main_menu
    ;;
  *)
    exit 0
    ;;
  esac
}

show_diagnostics_menu() {
  # Get state info
  local state_output
  state_output=$("$THEME_CTL" get-state 2>&1 || echo "Failed to get state")

  local choice
  choice=$(menu "Theme Diagnostics" \
    "󰋼 View State\n󰁯 Unlock Script\n󰋲 Clear Cache\n󰸉 Back" \
    -mesg "Current: $DISPLAY_MODE")

  case "${choice}" in
  *"View State"*)
    notify-send "Theme State" "$state_output" -t 5000
    show_diagnostics_menu
    ;;
  *"Unlock"*)
    "$THEME_CTL" unlock
    notify-send "Theme" "Lock file removed" -t 2000
    show_diagnostics_menu
    ;;
  *"Clear Cache"*)
    rm -rf "$CACHE_DIR"
    mkdir -p "$CACHE_DIR"
    notify-send "Theme" "Thumbnail cache cleared" -t 2000
    show_diagnostics_menu
    ;;
  *"Back"*)
    show_appearance_menu
    ;;
  *)
    exit 0
    ;;
  esac
}

select_wallpaper() {
  [[ ! -d "$WALL_DIR" ]] || [[ ! -r "$WALL_DIR" ]] && {
    notify-send "Error" "Cannot access: $WALL_DIR"
    return 1
  }

  # Generate thumbnails
  local find_cmd
  find_cmd=$(build_find_cmd "$WALL_DIR")
  eval "$find_cmd" | xargs -P "$MAX_JOBS" -I {} bash -c 'gen_thumb "$@"' _ {}

  # Build selection list
  >"$TEMP_INPUT"
  while IFS= read -r img; do
    local thumb="$CACHE_DIR/$(basename "$img").png"
    [[ -f "$thumb" ]] && echo -en "$(basename "$img")\0icon\x1f$thumb\n" >>"$TEMP_INPUT"
  done < <(eval "$find_cmd")

  [[ ! -s "$TEMP_INPUT" ]] && {
    notify-send "No Wallpapers" "No images found in $WALL_DIR"
    return 1
  }

  # Show selection
  local selection
  # Grid Layout Overrides
  selection=$(rofi -dmenu -i -p "Select Wallpaper" \
    -theme-str 'window { width: 60%; }' \
    -theme-str 'listview { columns: 4; lines: 3; flow: horizontal; }' \
    -theme-str 'element { orientation: vertical; padding: 20px; spacing: 10px; }' \
    -theme-str 'element-icon { size: 150px; horizontal-align: 0.5; }' \
    -theme-str 'element-text { horizontal-align: 0.5; }' \
    -show-icons <"$TEMP_INPUT")

  [[ -n "$selection" ]] && [[ -f "$WALL_DIR/$selection" ]] &&
    run_app "$THEME_CTL" set-image "$WALL_DIR/$selection"
}

# --- SYSTEM MENU ---

show_system_menu() {
  local uptime kernel
  uptime=$(uptime -p | sed 's/up //' || echo "Unknown")
  kernel=$(uname -r || echo "Unknown")

  local choice
  choice=$(menu "System" \
    "󰢮 System Info\n󰑐 Refresh\n󰿅 Process Killer\n󰸉 Back" \
    -mesg "Uptime: $uptime | Kernel: $kernel")

  case "${choice,,}" in
  *info*)
    command -v kitty &>/dev/null &&
      kitty -e sh -c "fastfetch 2>/dev/null || neofetch 2>/dev/null || echo 'No system info tool'; read -p 'Press Enter...'" &
    ;;
  *refresh*) show_system_menu ;;
  *killer*)
    command -v kitty &>/dev/null &&
      kitty -e sh -c "hyprctl kill; read -p 'Click on window to close'" &
    ;;
  *back*) show_main_menu ;;
  *) exit 0 ;;
  esac
}

# --- POWER MENU ---

show_power_menu() {
  local choice
  choice=$(menu "Power" "󰐥 Shutdown\n󰜉 Reboot\n󰒲 Suspend\n󰤄 Lock\n󰗼 Logout\n󰸉 Back")

  case "$choice" in
  "󰐥 Shutdown") systemctl poweroff ;;
  "󰜉 Reboot") systemctl reboot ;;
  "󰒲 Suspend") systemctl suspend ;;
  "󰤄 Lock") loginctl lock-session ;;
  "󰗼 Logout") hyprctl dispatch exit ;;
  "󰸉 Back") show_main_menu ;;
  *) exit 0 ;;
  esac
}

# --- CONFIG MENU ---

show_config_menu() {
  local choice
  choice=$(menu "Configuration" "󱁉 Hyprland Config\n󰸉 Look & Feel\n󰆍 Keybinds\n󰸉 Back\n󱣱 Waybar\n󰪐 Animations")

  case "${choice,,}" in
  *hyprland*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/hypr/hyprland.conf & ;;
  *look*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/hypr/user-configs/looknfeel.conf & ;;
  *binds*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/hypr/user-configs/userbinds.conf & ;;
  *waybar*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/waybar/config.jsonc & ;;
  *animations*)
    command -v kitty &>/dev/null &
    kitty -e nvim ~/.config/hypr/user-configs/animations.conf &
    ;;
  *back*) show_main_menu ;;
  *) exit 0 ;;
  esac
}

# --- APPLICATIONS MENU ---

show_applications_menu() {
  rofi -show drun \
    -theme-str 'listview { columns: 4; lines: 6; }' \
    -theme-str 'element { orientation: vertical; children: [ element-icon, element-text ]; padding: 10px; }' \
    -theme-str 'element-icon { size: 64px; horizontal-align: 0.5; }' \
    -theme-str 'element-text { horizontal-align: 0.5; }' \
    -show-icons
}

# --- MAIN MENU ---

show_main_menu() {
  local choice
  choice=$(menu "Dashboard" "󱔗 Appearance\n󰀻 Applications\n System\n Configuration\n󰐥 Power")

  case "$choice" in
  "󱔗 Appearance") show_appearance_menu ;;
  "󰀻 Applications") show_applications_menu ;;
  " System") show_system_menu ;;
  " Configuration") show_config_menu ;;
  "󰐥 Power") show_power_menu ;;
  *) exit 0 ;;
  esac
}

# --- ENTRY POINT ---

main() {
  command -v rofi &>/dev/null || {
    notify-send "Error" "rofi is not installed"
    exit 1
  }

  [[ ! -x "$THEME_CTL" ]] && {
    notify-send "Error" "Theme controller not found: $THEME_CTL"
    exit 1
  }

  init_dirs

  if [[ -n "${1:-}" ]]; then
    case "$1" in
    --random) run_app "$THEME_CTL" random ;;
    --next) run_app "$THEME_CTL" next ;;
    --toggle) run_app "$THEME_CTL" toggle ;;
    --select) select_wallpaper ;;
    --theme-toggle) show_theme_toggle_menu ;;
    --diagnostics) show_diagnostics_menu ;;
    --applications) show_applications_menu ;;
    *) show_main_menu ;;
    esac
  else
    show_main_menu
  fi
}

main "$@"
