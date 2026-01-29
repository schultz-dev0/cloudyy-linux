#!/usr/bin/env bash

# =============================================================================
# HYPRLAND ROFI MENU (FIXED)
# =============================================================================

# --- CONFIGURATION ---
WALL_DIR="${HOME}/Wallpapers"
CACHE_DIR="${HOME}/.cache/matugen_thumbs"
STATE_FILE="${HOME}/.cache/rofi_wallpaper_current"
ROFI_THEME="${HOME}/.config/rofi/wallpaper.rasi"
THUMB_SIZE=250
MAX_PARALLEL_JOBS=$(nproc)
TEMP_ROFI_INPUT="/tmp/rofi_wallpaper_input_$$"
LOG_FILE="/tmp/rofi_wallpaper_debug.log"

# Cleanup temp file on exit
trap 'rm -f "$TEMP_ROFI_INPUT"' EXIT

# --- LOGGING HELPER ---
log() {
  echo "[$(date '+%H:%M:%S')] $1" >>"$LOG_FILE"
}

# --- INITIALIZATION ---
init_dirs() {
  mkdir -p "$CACHE_DIR" "$WALL_DIR"
}

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

count_wallpapers() {
  find_wallpapers | wc -l
}

get_random_wallpaper() {
  find_wallpapers | shuf -n 1
}

# --- DEPENDENCY CHECKS ---
check_dependencies() {
  local missing=()
  local deps=(rofi swww matugen hyprctl notify-send)

  for cmd in "${deps[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
    missing+=("imagemagick")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    notify-send "Missing Dependencies" "Required: ${missing[*]}"
    exit 1
  fi
}

# --- THUMBNAIL GENERATION ---
gen_thumb() {
  local img="$1"
  local filename=$(basename "$img")
  local thumb="$CACHE_DIR/${filename}.png"

  if [[ -f "$thumb" && "$thumb" -nt "$img" ]]; then
    return 0
  fi

  if command -v magick &>/dev/null; then
    magick "$img" -strip -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" \
      -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" \
      -quality 85 "$thumb" 2>/dev/null || return 1
  else
    convert "$img" -strip -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" \
      -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" \
      -quality 85 "$thumb" 2>/dev/null || return 1
  fi
}

export -f gen_thumb
export CACHE_DIR THUMB_SIZE

generate_all_thumbs() {
  local image_count=$(count_wallpapers)

  if [[ $image_count -eq 0 ]]; then
    notify-send "No Wallpapers Found" "Add images to $WALL_DIR"
    return 1
  fi

  if [[ $image_count -gt 50 ]]; then
    notify-send "Generating Thumbnails" "Processing $image_count wallpapers..."
  fi

  # Added -d '\n' to handle filenames with spaces correctly
  find_wallpapers | xargs -d '\n' -P "$MAX_PARALLEL_JOBS" -I {} bash -c 'gen_thumb "$@"' _ {}
}

# --- THEME APPLICATION ---
apply_theme() {
  local img="$1"

  log "Applying theme for: $img"

  if [[ ! -f "$img" ]]; then
    log "Error: File does not exist: $img"
    notify-send "Error" "Wallpaper file not found"
    return 1
  fi

  echo "$img" >"$STATE_FILE"

  # Run these sequentially first to debug, then background if slow
  matugen image "$img"
  swww img "$img" --transition-type grow --transition-pos "0.5,0.5" --transition-fps 60 &

  hyprctl reload &
  notify-send "Theme Synced" "Applied $(basename "$img")"
}

get_current_wallpaper() {
  [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE"
}

# --- CYCLE WALLPAPERS ---
cycle_wallpapers() {
  local interval="${1:-300}"

  notify-send "Wallpaper Cycle Started" "Changing every ${interval} seconds"

  local pid_file="/tmp/wallpaper_cycle.pid"
  echo $$ >"$pid_file"

  while true; do
    local random_wall=$(get_random_wallpaper)
    if [[ -n "$random_wall" ]]; then
      apply_theme "$random_wall"
    fi
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
      notify-send "Wallpaper Cycle Stopped"
    else
      rm -f "$pid_file"
    fi
  else
    notify-send "No Active Cycle" "Wallpaper cycle is not running"
  fi
}

# --- MENU FUNCTIONS ---
appearance_menu() {
  local current_wall=$(get_current_wallpaper)
  local current_name=""
  [[ -n "$current_wall" ]] && current_name="Current: $(basename "$current_wall")"

  local cycle_status=""
  if [[ -f "/tmp/wallpaper_cycle.pid" ]]; then
    local pid=$(cat "/tmp/wallpaper_cycle.pid")
    if kill -0 "$pid" 2>/dev/null; then
      cycle_status="(Cycle Active)"
    fi
  fi

  local sub_options="󰔎 Random Wallpaper\n󰸉 Select Wallpaper\n󰞘 Start Cycle (5min)\n󰓛 Stop Cycle\n󰆊 Clean Cache\n󰏘 Back"
  local sub_chosen=$(echo -e "$sub_options" | rofi -dmenu -i -p "Appearance $cycle_status" -mesg "$current_name")

  case $sub_chosen in
  "󰔎 Random Wallpaper")
    local random_wall=$(get_random_wallpaper)
    if [[ -n "$random_wall" ]]; then
      apply_theme "$random_wall"
    else
      notify-send "No Wallpapers" "Add images to $WALL_DIR"
    fi
    ;;

  "󰸉 Select Wallpaper")
    select_wallpaper
    ;;

  "󰞘 Start Cycle (5min)")
    local interval=$(echo -e "300\n600\n900\n1800\n3600" | rofi -dmenu -i -p "Cycle interval (seconds)")
    if [[ -n "$interval" ]]; then
      cycle_wallpapers "$interval" &
      disown
    fi
    ;;

  "󰓛 Stop Cycle")
    stop_cycle
    ;;

  "󰆊 Clean Cache")
    rm -rf "$CACHE_DIR"/*
    mkdir -p "$CACHE_DIR"
    notify-send "Cache Cleared" "Thumbnails will regenerate"
    ;;

  "󰏘 Back")
    main_menu
    ;;
  esac
}

select_wallpaper() {
  local wall_count=$(count_wallpapers)

  if [[ $wall_count -eq 0 ]]; then
    notify-send "No Wallpapers Found" "Add images to $WALL_DIR"
    return 1
  fi

  echo "Generating thumbnails..."
  generate_all_thumbs || return 1

  declare -A wallpaper_map
  >"$TEMP_ROFI_INPUT"

  log "Building wallpaper list..."
  while IFS= read -r img; do
    local name=$(basename "$img")
    local thumb="$CACHE_DIR/$name.png"
    wallpaper_map["$name"]="$img"
    [[ ! -f "$thumb" ]] && thumb="$img"
    printf '%s\0icon\x1f%s\n' "$name" "$thumb" >>"$TEMP_ROFI_INPUT"
  done < <(find_wallpapers)

  if [[ ! -s "$TEMP_ROFI_INPUT" ]]; then
    notify-send "Error" "Failed to build wallpaper list"
    return 1
  fi

  local map_file="/tmp/wallpaper_map_$$"
  # Save map to file
  for name in "${!wallpaper_map[@]}"; do
    echo "$name|${wallpaper_map[$name]}" >>"$map_file"
  done

  log "Launching Rofi..."
  local selected_name
  if [[ -f "$ROFI_THEME" ]]; then
    selected_name=$(rofi -dmenu -i -p "󰸉 Wallpapers ($wall_count)" -show-icons -theme "$ROFI_THEME" <"$TEMP_ROFI_INPUT")
  else
    selected_name=$(rofi -dmenu -i -p "󰸉 Wallpapers ($wall_count)" -show-icons <"$TEMP_ROFI_INPUT")
  fi

  log "Rofi returned: '$selected_name'"

  if [[ -n "$selected_name" ]]; then
    # Fix: Limit grep to 1 result (-m 1) to prevent multiline errors
    local full_path=$(grep -F -m 1 "$selected_name|" "$map_file" | cut -d'|' -f2)

    if [[ -n "$full_path" && -f "$full_path" ]]; then
      log "Applying path: $full_path"
      apply_theme "$full_path"
    else
      log "Error: Could not find path for $selected_name"
      notify-send "Error" "Could not find: $selected_name"
    fi
  fi

  rm -f "$map_file"
}

power_menu() {
  local p_options="󰐥 Shutdown\n󰜉 Reboot\n󰒲 Suspend\n󰤄 Lock\n󰗼 Logout\n󰏘 Back"
  local p_chosen=$(echo -e "$p_options" | rofi -dmenu -i -p "Power")

  case $p_chosen in
  "󰐥 Shutdown") confirm_action "Shutdown" && systemctl poweroff ;;
  "󰜉 Reboot") confirm_action "Reboot" && systemctl reboot ;;
  "󰒲 Suspend") systemctl suspend ;;
  "󰤄 Lock")
    if command -v hyprlock &>/dev/null; then
      hyprlock
    elif command -v swaylock &>/dev/null; then
      swaylock
    else notify-send "Error" "No lock screen available"; fi
    ;;
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
  local uptime=$(uptime -p 2>/dev/null | sed 's/up //' || echo "unknown")
  local kernel=$(uname -r)
  local cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "?")
  local mem_usage=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}' || echo "unknown")

  local info="Uptime: $uptime\nKernel: $kernel\nCPU: ${cpu_usage}%\nMemory: $mem_usage"

  local s_options="󰌢 System Info\n󰑓 Refresh\n󰏘 Back"
  local s_chosen=$(echo -e "$s_options" | rofi -dmenu -i -p "System" -mesg "$info")

  case $s_chosen in
  "󰌢 System Info")
    command -v kitty &>/dev/null &&
      kitty -e sh -c "fastfetch 2>/dev/null || echo 'fastfetch not installed'; read -p 'Press enter...'" &
    ;;
  "󰑓 Refresh") system_menu ;;
  "󰏘 Back") main_menu ;;
  esac
}

main_menu() {
  local options="󱔗 Appearance\n󰀻 Applications\n󰍉 System\n󰐥 Power"
  local chosen=$(echo -e "$options" | rofi -dmenu -i -p "󱓞 Launch Menu")

  case $chosen in
  "󱔗 Appearance") appearance_menu ;;
  "󰀻 Applications") rofi -show drun ;;
  "󰍉 System") system_menu ;;
  "󰐥 Power") power_menu ;;
  esac
}

# --- MAIN EXECUTION ---
main() {
  check_dependencies
  init_dirs
  main_menu
}

case "${1:-}" in
--random)
  init_dirs
  random_wall=$(get_random_wallpaper)
  [[ -n "$random_wall" ]] && apply_theme "$random_wall"
  ;;
--cycle)
  init_dirs
  cycle_wallpapers "${2:-300}"
  ;;
--stop-cycle) stop_cycle ;;
--generate-thumbs)
  init_dirs
  generate_all_thumbs
  ;;
--test)
  init_dirs
  echo "=== Wallpaper Detection Test ==="
  echo "Directory: $WALL_DIR"
  echo "Wallpapers found: $(count_wallpapers)"
  find_wallpapers | head -10
  ;;
--list)
  init_dirs
  find_wallpapers
  ;;
*) main ;;
esac
