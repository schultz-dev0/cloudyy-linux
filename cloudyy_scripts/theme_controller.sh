#!/usr/bin/env bash
set -euo pipefail

# --- CONFIGURATION ---
readonly STATE_DIR="${HOME}/.config/hypr/theme_state"
readonly STATE_FILE="${STATE_DIR}/state.conf"
readonly PUBLIC_STATE="${STATE_DIR}/state" # 0 for dark, 1 for light
readonly LOCK_FILE="/tmp/theme_ctl.lock"
readonly BASE_WALL_DIR="${HOME}/Wallpapers"
readonly TEMP_FRAME="/tmp/current_theme_frame.png"
readonly OBSIDIAN_CONF="$HOME/MyLife/.obsidian/appearance.json"

# --- ATOMIC LOCKING ---
# Prevents script from running over itself if you spam the keybind.
exec 200>"$LOCK_FILE"
flock -n 200 || {
  echo "Theme switch already in progress. Ignoring."
  exit 0
}

# --- STATE MANAGEMENT ---
read_state() {
  THEME_MODE="dark"
  CURRENT_WALL=""
  [[ -f "$STATE_FILE" ]] && source "$STATE_FILE" 2>/dev/null || true
}

save_state() {
  mkdir -p "$STATE_DIR"
  # Internal State
  cat <<EOF >"$STATE_FILE"
THEME_MODE="$THEME_MODE"
CURRENT_WALL="$CURRENT_WALL"
EOF
  # Public State (0/1) for other scripts to read easily
  [[ "$THEME_MODE" == "light" ]] && echo 1 >"$PUBLIC_STATE" || echo 0 >"$PUBLIC_STATE"
}

# --- PROCESS UTILS ---
wait_for_process() {
  local proc="$1"
  local timeout=20
  while ! pgrep -x "$proc" &>/dev/null && [ $timeout -gt 0 ]; do
    sleep 0.1
    ((timeout--))
  done
}

# --- APPLICATION UPDATES ---
update_apps() {
  # 1. GTK / System Mode
  local scheme='prefer-dark'
  [[ "$THEME_MODE" == "light" ]] && scheme='prefer-light'
  gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || true

  # 2. Obsidian Sync
  if [[ -f "$OBSIDIAN_CONF" ]]; then
    sed -i 's/"baseTheme": *"[^"]*"/"baseTheme": "'"$THEME_MODE"'"/' "$OBSIDIAN_CONF"
    touch "$OBSIDIAN_CONF"
  fi
}

reload_ui() {
  # Restart Waybar using your robust restart script
  "$HOME/cloudyy_scripts/restart_waybar.sh" >/dev/null 2>&1 &

  # Reload SwayNC
  swaync-client -rs >/dev/null 2>&1 &
}

# --- CORE LOGIC ---
extract_frame() {
  ffmpeg -i "$1" -vframes 1 -y -loglevel error "$TEMP_FRAME" 2>/dev/null ||
    magick "${1}[0]" "$TEMP_FRAME" 2>/dev/null
}

generate_colors() {
  local img="$1"
  local mat_in="$img"
  local mime=$(file --mime-type -b "$img")

  [[ "$mime" == *"video/"* || "$mime" == *"image/gif"* ]] && extract_frame "$img" && mat_in="$TEMP_FRAME"

  if matugen image "$mat_in" -m "$THEME_MODE" >/dev/null 2>&1; then
    update_apps
    reload_ui
  else
    notify-send "Matugen Failed" "Could not generate colors."
  fi
}

apply_wallpaper() {
  local img="$1"
  [[ -f "$img" ]] || return 1

  CURRENT_WALL="$img"
  save_state
  generate_colors "$img"

  local mime=$(file --mime-type -b "$img")
  if [[ "$mime" == *"video/"* || "$mime" == *"image/gif"* ]]; then
    pkill -9 mpvpaper 2>/dev/null || true
    pkill -9 swww-daemon 2>/dev/null || true
    sleep 0.2
    mpvpaper -o "no-audio loop-playlist hwdec=auto panscan=1.0" '*' "$img" >/dev/null 2>&1 &
    disown
  else
    pkill -9 mpvpaper 2>/dev/null || true
    # Ensure swww is alive
    pgrep -x swww-daemon >/dev/null || {
      swww-daemon --format xrgb &
      disown
      sleep 0.5
    }
    swww img "$img" --transition-type random --transition-duration 1.5 --transition-fps 60
  fi
}

# --- COMMANDS ---

cmd_toggle() {
  read_state
  [[ "$THEME_MODE" == "dark" ]] && THEME_MODE="light" || THEME_MODE="dark"

  # Self-Healing: If we don't know the wall, ask swww
  if [[ -z "$CURRENT_WALL" || ! -f "$CURRENT_WALL" ]]; then
    CURRENT_WALL=$(swww query 2>/dev/null | grep -oP 'image: \K.*' | head -n1)
  fi

  save_state
  notify-send "Theme" "Switching to ${THEME_MODE}..." -h string:x-canonical-private-synchronous:theme

  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    generate_colors "$CURRENT_WALL"
  else
    update_apps
    reload_ui
  fi
}

# --- DISPATCH ---
read_state
case "${1:-}" in
set-image) apply_wallpaper "$(realpath "$2")" ;;
toggle) cmd_toggle ;;
random)
  folder_mode="$(tr '[:lower:]' '[:upper:]' <<<${THEME_MODE:0:1})${THEME_MODE:1}"
  target="$BASE_WALL_DIR/$folder_mode"
  shopt -s nullglob globstar
  walls=("$target"/**/*.{jpg,jpeg,png,gif,webp,mp4,mkv})
  [[ ${#walls[@]} -gt 0 ]] && apply_wallpaper "${walls[RANDOM % ${#walls[@]}]}"
  ;;
get-mode) echo "$THEME_MODE" ;;
*)
  echo "Usage: $0 {set-image|toggle|random|get-mode}"
  exit 1
  ;;
esac
