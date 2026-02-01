#!/usr/bin/env bash
# ==============================================================================
# THEME CONTROLLER (Fixed for Arch/Hyprland)
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION ---
readonly BASE_WALL_DIR="${HOME}/Wallpapers"
readonly LIGHT_DIR="${BASE_WALL_DIR}/Light"
readonly DARK_DIR="${BASE_WALL_DIR}/Dark"

readonly STATE_DIR="${HOME}/.config/hypr/theme_state"
readonly STATE_FILE="${STATE_DIR}/state.conf"
readonly PUBLIC_STATE="${STATE_DIR}/state"
readonly LOCK_FILE="/tmp/theme_ctl.lock"
readonly OBSIDIAN_CONF="$HOME/Documents/Obsidian Vault/.obsidian/appearance.json"

# Defaults
THEME_MODE="dark"
CURRENT_WALL=""

# --- LOGGING & LOCKING ---
log() { echo "[THEME] $*" >&2; }
die() {
  log "ERROR: $*"
  notify-send "Theme Error" "$*" -u critical 2>/dev/null || true
  exit 1
}

# Check dependencies
check_deps() {
  local missing=()
  command -v matugen >/dev/null 2>&1 || missing+=("matugen")
  command -v swww >/dev/null 2>&1 || missing+=("swww")
  command -v mpvpaper >/dev/null 2>&1 || missing+=("mpvpaper")

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing dependencies: ${missing[*]}"
  fi
}

# Clean stale locks (older than 30 seconds)
clean_stale_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
    if [[ $lock_age -gt 30 ]]; then
      log "Removing stale lock (${lock_age}s old)"
      rm -f "$LOCK_FILE"
    fi
  fi
}

# Atomic Lock
acquire_lock() {
  clean_stale_lock
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    log "Locked: Another instance is running"
    exit 0
  fi
}

# --- STATE MANAGEMENT ---
read_state() {
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE" 2>/dev/null || true
  fi
  [[ -z "${THEME_MODE:-}" ]] && THEME_MODE="dark"

  # Validate state against actual wallpaper location
  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    if [[ "$CURRENT_WALL" == "$LIGHT_DIR"/* ]]; then
      if [[ "$THEME_MODE" != "light" ]]; then
        log "Warning: State mismatch detected. Wallpaper is in Light dir but mode was $THEME_MODE. Correcting to light."
        THEME_MODE="light"
      fi
    elif [[ "$CURRENT_WALL" == "$DARK_DIR"/* ]]; then
      if [[ "$THEME_MODE" != "dark" ]]; then
        log "Warning: State mismatch detected. Wallpaper is in Dark dir but mode was $THEME_MODE. Correcting to dark."
        THEME_MODE="dark"
      fi
    fi
  fi

  log "Current state: mode=$THEME_MODE, wall=$CURRENT_WALL"
}

save_state() {
  mkdir -p "$STATE_DIR"
  cat <<EOF >"$STATE_FILE"
THEME_MODE="$THEME_MODE"
CURRENT_WALL="$CURRENT_WALL"
EOF
  # Write 1 for Light, 0 for Dark
  if [[ "$THEME_MODE" == "light" ]]; then
    echo 1 >"$PUBLIC_STATE"
  else
    echo 0 >"$PUBLIC_STATE"
  fi
  log "State saved: $THEME_MODE"
}

# --- SYNC APPS ---
update_apps() {
  local scheme='prefer-dark'
  [[ "$THEME_MODE" == "light" ]] && scheme='prefer-light'

  log "Updating apps to $scheme"

  # GTK - don't fail if gsettings isn't available
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || {
      log "Warning: gsettings failed (non-critical)"
    }
  fi

  # Obsidian
  if [[ -f "$OBSIDIAN_CONF" ]]; then
    local tmp=$(mktemp)
    if sed 's/"baseTheme": *"[^"]*"/"baseTheme": "'"$THEME_MODE"'"/' "$OBSIDIAN_CONF" >"$tmp" 2>/dev/null; then
      mv "$tmp" "$OBSIDIAN_CONF"
      log "Updated Obsidian theme"
    else
      rm -f "$tmp"
      log "Warning: Failed to update Obsidian (non-critical)"
    fi
  fi
}

reload_ui() {
  log "Reloading UI components"

  # Waybar
  if [[ -x "$HOME/cloudyy_scripts/restart_waybar.sh" ]]; then
    "$HOME/cloudyy_scripts/restart_waybar.sh" >/dev/null 2>&1 &
  else
    pkill waybar 2>/dev/null || true
    sleep 0.2
    waybar &
    disown
  fi

  # SwayNC
  if command -v swaync-client >/dev/null 2>&1; then
    swaync-client -rs >/dev/null 2>&1 &
  fi

  # Thunar
  if pgrep -x thunar >/dev/null 2>&1; then
    log "Restarting Thunar"
    pkill thunar 2>/dev/null || true
    sleep 0.3
    thunar --daemon &
    disown
  fi
}

# --- CORE LOGIC ---
extract_frame() {
  local input="$1"
  local output="$2"

  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -i "$input" -vframes 1 -y -loglevel error "$output" 2>/dev/null && return 0
  fi

  if command -v magick >/dev/null 2>&1; then
    magick "${input}[0]" "$output" 2>/dev/null && return 0
  fi

  log "Warning: Neither ffmpeg nor imagemagick available for frame extraction"
  return 1
}

generate_colors() {
  local img="$1"
  local mat_input="$img"
  local mime=$(file --mime-type -b "$img")

  log "Generating colors from: $img (type: $mime)"

  if [[ "$mime" == *"video/"* || "$mime" == *"image/gif"* ]]; then
    local temp_frame="/tmp/theme_frame.png"
    if extract_frame "$img" "$temp_frame"; then
      mat_input="$temp_frame"
    else
      log "Warning: Using original file for color generation"
    fi
  fi

  if matugen image "$mat_input" -m "$THEME_MODE" 2>&1 | tee /tmp/matugen.log; then
    log "Matugen succeeded"
    update_apps
    reload_ui
  else
    log "ERROR: Matugen failed, check /tmp/matugen.log"
    notify-send "Theme Error" "Matugen failed to generate colors" 2>/dev/null || true
    return 1
  fi
}

apply_wallpaper() {
  local img="$1"
  [[ -f "$img" ]] || die "Wallpaper not found: $img"

  log "Applying wallpaper: $img"

  CURRENT_WALL="$img"
  save_state
  generate_colors "$img" || log "Warning: Color generation failed"

  local mime=$(file --mime-type -b "$img")

  # Video/GIF wallpapers
  if [[ "$mime" == *"video/"* || "$mime" == *"image/gif"* ]]; then
    log "Setting animated wallpaper with mpvpaper"
    pkill -9 mpvpaper 2>/dev/null || true
    pkill -9 swww-daemon 2>/dev/null || true
    sleep 0.2

    # Launch without holding the lock
    mpvpaper -o "no-audio loop-playlist hwdec=auto panscan=1.0" '*' "$img" >/dev/null 2>&1 200>&- &
    disown
  else
    # Static wallpapers
    log "Setting static wallpaper with swww"
    pkill -9 mpvpaper 2>/dev/null || true

    if ! pgrep -x swww-daemon >/dev/null; then
      log "Starting swww-daemon"
      swww-daemon --format xrgb 200>&- &
      disown
      sleep 0.5
    fi

    swww img "$img" --transition-type random --transition-duration 1.5 --transition-fps 60 200>&- &
  fi

  log "Wallpaper applied successfully"
}

# --- COMMANDS ---

cmd_toggle() {
  read_state

  # Debounce: check if last toggle was less than 2 seconds ago
  local last_toggle_file="/tmp/theme_ctl_last_toggle"
  local current_time=$(date +%s)
  if [[ -f "$last_toggle_file" ]]; then
    local last_time=$(cat "$last_toggle_file")
    local time_diff=$((current_time - last_time))
    if [[ $time_diff -lt 2 ]]; then
      log "Toggle debounced (${time_diff}s since last toggle, waiting 2s minimum)"
      notify-send "Theme" "Please wait before toggling again" 2>/dev/null || true
      exit 0
    fi
  fi
  echo "$current_time" >"$last_toggle_file"

  local new_mode="dark"
  [[ "$THEME_MODE" == "dark" ]] && new_mode="light"
  log "Toggling from $THEME_MODE to $new_mode"
  cmd_set --mode "$new_mode"
}

cmd_set() {
  local new_mode=""
  while (($# > 0)); do
    case "$1" in
    --mode)
      new_mode="$2"
      shift 2
      ;;
    *) shift ;;
    esac
  done

  read_state
  [[ -n "$new_mode" ]] && THEME_MODE="$new_mode"
  save_state

  # Strict directory selection
  local target_dir=""
  if [[ "$THEME_MODE" == "light" ]]; then
    target_dir="$LIGHT_DIR"
  else
    target_dir="$DARK_DIR"
  fi

  log "Looking for wallpapers in: $target_dir"
  [[ -d "$target_dir" ]] || die "Folder missing: $target_dir"

  # Find wallpapers
  shopt -s nullglob globstar nocaseglob
  local walls=("$target_dir"/**/*.{jpg,jpeg,png,gif,webp,mp4,mkv})
  shopt -u nullglob globstar nocaseglob

  log "Found ${#walls[@]} wallpapers"

  if [[ ${#walls[@]} -gt 0 ]]; then
    local rand_wall="${walls[RANDOM % ${#walls[@]}]}"
    log "Selected: $rand_wall"
    notify-send "Theme" "Switching to $THEME_MODE..." 2>/dev/null || true
    apply_wallpaper "$rand_wall"
  else
    die "No wallpapers found in $target_dir"
  fi
}

# --- MAIN ---

# Check dependencies first
check_deps

# Acquire lock
acquire_lock

# Main command dispatch
case "${1:-}" in
set)
  shift
  cmd_set "$@"
  ;;
toggle)
  cmd_toggle
  ;;
random)
  read_state
  cmd_set --mode "$THEME_MODE"
  ;;
refresh)
  read_state
  if [[ -f "$CURRENT_WALL" ]]; then
    log "Refreshing colors for current wallpaper"
    generate_colors "$CURRENT_WALL"
  else
    log "No current wallpaper, selecting random"
    cmd_set --mode "$THEME_MODE"
  fi
  ;;
set-image)
  [[ -z "${2:-}" ]] && die "Usage: set-image <path>"
  read_state
  apply_wallpaper "$(realpath "$2")"
  ;;
get-mode)
  read_state
  echo "$THEME_MODE"
  ;;
*)
  echo "Usage: $0 {set --mode <light|dark> | toggle | random | refresh | set-image <path> | get-mode}"
  exit 1
  ;;
esac

log "Done!"
