#!/usr/bin/env bash

# =============================================================================
# HYPRLAND ROFI MENU (UNIVERSAL + BACKEND INTEGRATION)
# =============================================================================

# --- CONFIGURATION ---
# Backend Controller
THEME_CTL="${HOME}/cloudyy_scripts/theme_controller.sh"

# Directories
WALL_DIR="${HOME}/Wallpapers"
CACHE_DIR="${HOME}/.cache/rofi_thumbs"
ROFI_THEME="${HOME}/.config/rofi/wallpaper.rasi"

# Settings
THUMB_SIZE=250
MAX_PARALLEL_JOBS=$(nproc)
TEMP_ROFI_INPUT="/tmp/rofi_wallpaper_input_$$"
LOG_FILE="/tmp/rofi_wallpaper_debug.log"

# Cleanup temp file on exit
trap 'rm -f "$TEMP_ROFI_INPUT"' EXIT

# --- CHECK BACKEND ---
if [[ ! -x "$THEME_CTL" ]]; then
  notify-send "Error" "theme_controller.sh not found or not executable!"
  exit 1
fi

# --- LOGGING HELPER ---
log() { echo "[$(date '+%H:%M:%S')] $1" >>"$LOG_FILE"; }

# --- INITIALIZATION ---
init_dirs() { mkdir -p "$CACHE_DIR" "$WALL_DIR"; }

# --- FIND WALLPAPERS ---
find_wallpapers() {

  shopt -s nullglob nocaseglob

  local files=()

  files+=("$WALL_DIR"/*.jpg)

  files+=("$WALL_DIR"/*.jpeg)

  files+=("$WALL_DIR"/*.png)

  files+=("$WALL_DIR"/*.webp)

  files+=("$WALL_DIR"/*.gif)

  files+=("$WALL_DIR"/*/*.jpg)

  files+=("$WALL_DIR"/*/*.jpeg)

  files+=("$WALL_DIR"/*/*.png)

  files+=("$WALL_DIR"/*/*.webp)

  files+=("$WALL_DIR"/*/*.gif)

  shopt -u nullglob nocaseglob

  for file in "${files[@]}"; do

    [[ -f "$file" ]] && echo "$file"

  done | sort -u

}

count_wallpapers() { find_wallpapers | wc -l; }

# --- THUMBNAIL GENERATION ---
gen_thumb() {
  local img="$1"
  local filename=$(basename "$img")
  local thumb="$CACHE_DIR/${filename}.png"
  [[ -f "$thumb" && "$thumb" -nt "$img" ]] && return 0

  # Try magick first, fallback to convert
  if command -v magick &>/dev/null; then
    magick "$img" -strip -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" -quality 85 "$thumb" 2>/dev/null
  else
    convert "$img" -strip -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" -quality 85 "$thumb" 2>/dev/null
  fi
}
export -f gen_thumb
export CACHE_DIR THUMB_SIZE

generate_all_thumbs() {
  local count=$(count_wallpapers)
  [[ $count -eq 0 ]] && {
    notify-send "No Wallpapers" "Check $WALL_DIR"
    return 1
  }
  [[ $count -gt 50 ]] && notify-send "Generating Thumbnails" "Processing $count images..."

  find_wallpapers | xargs -d '\n' -P "$MAX_PARALLEL_JOBS" -I {} bash -c 'gen_thumb "$@"' _ {}
}

# --- THEME APPLICATION (Delegates to Backend) ---
apply_theme() {
  local img="$1"
  log "Delegating to backend: $img"

  # DIRECT EXECUTION (No uwsm-app needed here)
  "$THEME_CTL" set-image "$img"

  notify-send "Theme Synced" "Applied $(basename "$img")"
}

apply_random() {
  "$THEME_CTL" random
}

cycle_wallpapers() {
  # ...
  while true; do
    "$THEME_CTL" random
    sleep "$interval"
  done
}

stop_cycle() {
  local pid_file="/tmp/wallpaper_cycle.pid"
  if [[ -f "$pid_file" ]]; then
    local pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      rm -f "$pid_file"
      notify-send "Cycle Stopped"
    else
      rm -f "$pid_file"
    fi
  else
    notify-send "No Active Cycle"
  fi
}

# --- MENU FUNCTIONS ---

appearance_menu() {
  local cycle_status=""
  [[ -f "/tmp/wallpaper_cycle.pid" ]] && kill -0 $(cat "/tmp/wallpaper_cycle.pid") 2>/dev/null && cycle_status="(Cycle Active)"

  local sub_options="󰔎 Random Wallpaper\n󰸉 Select Wallpaper\n󰞘 Start Cycle (5min)\n󰓛 Stop Cycle\n󰆊 Clean Cache\n󰏘 Back"
  local sub_chosen=$(echo -e "$sub_options" | rofi -dmenu -i -p "Appearance $cycle_status")

  case $sub_chosen in
  "󰔎 Random Wallpaper") apply_random ;;
  "󰸉 Select Wallpaper") select_wallpaper ;;
  "󰞘 Start Cycle (5min)")
    cycle_wallpapers 300 &
    disown
    ;;
  "󰓛 Stop Cycle") stop_cycle ;;
  "󰆊 Clean Cache")
    rm -rf "$CACHE_DIR"/*
    notify-send "Cache Cleared"
    ;;
  "󰏘 Back") main_menu ;;
  esac
}

select_wallpaper() {
  echo "Generating thumbnails..."
  generate_all_thumbs || return 1

  declare -A wallpaper_map
  >"$TEMP_ROFI_INPUT"

  log "Building list..."
  while IFS= read -r img; do
    local name=$(basename "$img")
    local thumb="$CACHE_DIR/$name.png"
    wallpaper_map["$name"]="$img"
    [[ ! -f "$thumb" ]] && thumb="$img"
    printf '%s\0icon\x1f%s\n' "$name" "$thumb" >>"$TEMP_ROFI_INPUT"
  done < <(find_wallpapers)

  local selected_name
  if [[ -f "$ROFI_THEME" ]]; then
    selected_name=$(rofi -dmenu -i -p "󰸉 Select" -show-icons -theme "$ROFI_THEME" <"$TEMP_ROFI_INPUT")
  else
    selected_name=$(rofi -dmenu -i -p "󰸉 Select" -show-icons <"$TEMP_ROFI_INPUT")
  fi

  if [[ -n "$selected_name" ]]; then
    local full_path="${wallpaper_map[$selected_name]}"
    [[ -f "$full_path" ]] && apply_theme "$full_path"
  fi
}

power_menu() {
  local p_options="󰐥 Shutdown\n󰜉 Reboot\n󰒲 Suspend\n󰤄 Lock\n󰗼 Logout\n󰏘 Back"
  local p_chosen=$(echo -e "$p_options" | rofi -dmenu -i -p "Power")

  case $p_chosen in
  "󰐥 Shutdown") confirm_action "Shutdown" && systemctl poweroff ;;
  "󰜉 Reboot") confirm_action "Reboot" && systemctl reboot ;;
  "󰒲 Suspend") systemctl suspend ;;
  "󰤄 Lock") loginctl lock-session ;;
  "󰗼 Logout") confirm_action "Logout" && hyprctl dispatch exit ;;
  "󰏘 Back") main_menu ;;
  esac
}

confirm_action() {
  local action="$1"
  local confirm=$(echo -e "Yes\nNo" | rofi -dmenu -i -p "Confirm $action?")
  [[ "$confirm" == "Yes" ]]
}

system_menu() {
  local uptime=$(uptime -p | sed 's/up //')
  local kernel=$(uname -r)
  local info="Uptime: $uptime\nKernel: $kernel"

  local s_options="󰌢 System Info\n󰑓 Refresh\n󰏘 Back"
  local s_chosen=$(echo -e "$s_options" | rofi -dmenu -i -p "System" -mesg "$info")

  case $s_chosen in
  "󰌢 System Info")
    command -v kitty &>/dev/null && kitty -e sh -c "fastfetch; read -p 'Enter...'" &
    ;;
  "󰑓 Refresh") system_menu ;;
  "󰏘 Back") main_menu ;;
  esac
}

main_menu() {
  local options="󱔗 Appearance\n󰀻 Applications\n󰍉 System\n󰐥 Power"
  local chosen=$(echo -e "$options" | rofi -dmenu -i -p "Menu")

  case $chosen in
  "󱔗 Appearance") appearance_menu ;;
  "󰀻 Applications") rofi -show drun ;;
  "󰍉 System") system_menu ;;
  "󰐥 Power") power_menu ;;
  esac
}

# --- MAIN ---
if [[ $# -eq 0 ]]; then
  # No arguments? Open the Main Menu
  init_dirs
  main_menu
else
  # Handle specific arguments for keybinds
  case "$1" in
  --random)
    init_dirs
    apply_random
    ;;
  --select)
    init_dirs
    select_wallpaper
    ;;
  *)
    init_dirs
    main_menu
    ;;
  esac
fi
