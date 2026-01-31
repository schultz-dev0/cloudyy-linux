#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# HYPRLAND DASHBOARD (ROFI FRONTEND)
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

readonly SUPPORTED_FORMATS=("*.jpg" "*.jpeg" "*.png" "*.gif" "*.mp4" "*.webp" "*.mkv")

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

# --- APPEARANCE MENU ---

show_appearance_menu() {
  local icon=""
  [[ "$CURRENT_MODE" == "light" ]] && icon=""

  local choice
  choice=$(menu "Theme: $DISPLAY_MODE" \
    "$icon Toggle Mode ($DISPLAY_MODE)\n󰔎 Random ($DISPLAY_MODE)\n󰸉 Select Wallpaper\n󰆊 Clean Cache\n󰏘 Back")

  case "${choice,,}" in
  *toggle*) run_app "$THEME_CTL" toggle ;;
  *random*) run_app "$THEME_CTL" random ;;
  *select*) select_wallpaper ;;
  *clean*)
    rm -rf "${CACHE_DIR:?}"/*
    notify-send "Cache Cleared" "Thumbnail cache emptied"
    show_appearance_menu
    ;;
  *back*) show_main_menu ;;
  *) exit 0 ;;
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
  selection=$(rofi -dmenu -i -p "Select Wallpaper" -show-icons <"$TEMP_INPUT")

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
    "󰌢 System Info\n󰑓 Refresh\n󰿅 Process Killer\n󰏘 Back" \
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
  choice=$(menu "Power" "󰐥 Shutdown\n󰜉 Reboot\n󰒲 Suspend\n󰤄 Lock\n󰗼 Logout\n󰏘 Back")

  case "$choice" in
  "󰐥 Shutdown") systemctl poweroff ;;
  "󰜉 Reboot") systemctl reboot ;;
  "󰒲 Suspend") systemctl suspend ;;
  "󰤄 Lock") loginctl lock-session ;;
  "󰗼 Logout") hyprctl dispatch exit ;;
  "󰏘 Back") show_main_menu ;;
  *) exit 0 ;;
  esac
}

# --- CONFIG MENU ---

show_config_menu() {
  local choice
  choice=$(menu "Configuration" " Hyprland Config\n󰸉 Look & Feel\n󰆊 Keybinds\n󰏘 Back\n Waybar\n Animations")

  case "${choice,,}" in
  *hyprland*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/hypr/hyprland.conf & ;;
  *look*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/hypr/user-configs/looknfeel.conf & ;;
  *binds*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/hypr/user-configs/userbinds.conf & ;;
  *waybar*) command -v kitty &>/dev/null && kitty -e nvim ~/.config/waybar/config.jsonc & ;;
  *animations*)
    command -v kitty &>/dev/null &
    kitty -e nvim ~/.config/hypr/user-configs/animations &
    ;;
  *back*) show_main_menu ;;
  *) exit 0 ;;
  esac
}

# --- MAIN MENU ---

show_main_menu() {
  local choice
  choice=$(menu "Dashboard" "󱔗 Appearance\n󰀻 Applications\n󰍉 System\n Configuration\n󰐥 Power")

  case "$choice" in
  "󱔗 Appearance") show_appearance_menu ;;
  "󰀻 Applications") rofi -show drun ;;
  "󰍉 System") show_system_menu ;;
  " Configuration") show_config_menu ;;
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
    --select) select_wallpaper ;;
    *) show_main_menu ;;
    esac
  else
    show_main_menu
  fi
}

main "$@"
