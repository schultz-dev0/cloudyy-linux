#!/usr/bin/env bash
# ==============================================================================
# THEME CONTROLLER (Improved Version)
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION ---
readonly WALL_DIR="${HOME}/Wallpapers"
readonly STATE_DIR="${HOME}/.config/hypr/theme_state"
readonly STATE_FILE="${STATE_DIR}/state.conf"
readonly PUBLIC_STATE="${STATE_DIR}/state"

# --- LOGGING ---
log() { printf '\033[1;34m[THEME]\033[0m %s\n' "$*" >&2; }
notify() { notify-send "Theme Controller" "$1" -u "${2:-normal}" -t 3000 2>/dev/null || true; }
die() {
  log "ERROR: $*"
  notify "Error: $*" critical
  exit 1
}

# --- STATE MANAGEMENT ---

read_state() {
  THEME_MODE="dark"
  CURRENT_WALL=""

  if [[ -f "$STATE_FILE" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      [[ $key =~ ^# ]] && continue
      value="${value%\"}"
      value="${value#\"}"
      case "$key" in
      THEME_MODE) THEME_MODE="$value" ;;
      CURRENT_WALL) CURRENT_WALL="$value" ;;
      esac
    done <"$STATE_FILE"
  fi
}

save_state() {
  mkdir -p "$STATE_DIR"
  cat <<EOF >"$STATE_FILE"
THEME_MODE="$THEME_MODE"
CURRENT_WALL="$CURRENT_WALL"
EOF
  # Waybar signal: 1=Light, 0=Dark
  echo "$([[ "$THEME_MODE" == "light" ]] && echo 1 || echo 0)" >"$PUBLIC_STATE"
}

# --- HELPERS ---

get_wallpapers() {
  # Clear array first
  walls=()

  # Expand tilde to actual home directory
  local wall_dir="${WALL_DIR/#\~/$HOME}"

  # Check directory exists
  if [[ ! -d "$wall_dir" ]]; then
    log "Directory does not exist: $wall_dir"
    die "Directory not found: $wall_dir"
  fi

  # Check if directory is readable
  if [[ ! -r "$wall_dir" ]]; then
    die "Directory not readable: $wall_dir"
  fi

  log "Searching for wallpapers in: $wall_dir"

  # Find command (Recursive & Case Insensitive)
  # Using mapfile for better handling
  mapfile -d '' walls < <(find -L "$wall_dir" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -print0 2>/dev/null | sort -z)

  # Debug output
  log "Found ${#walls[@]} wallpaper(s)"

  if ((${#walls[@]} == 0)); then
    log "Contents of $wall_dir:"
    ls -lah "$wall_dir" >&2 || true
    die "No wallpapers found in $wall_dir"
  fi

  # Show first few wallpapers for debugging
  if [[ "${DEBUG:-0}" == "1" ]]; then
    log "Sample wallpapers:"
    for i in "${!walls[@]}"; do
      if ((i < 3)); then
        log "  [$i] ${walls[$i]}"
      fi
    done
  fi
}

ensure_swww() {
  if ! pgrep -x swww-daemon >/dev/null; then
    log "Starting swww-daemon..."
    swww-daemon --format xrgb >/dev/null 2>&1 &
    sleep 1
  fi
}

generate_colors() {
  local img="$1"
  local mode="$2"

  log "Generating colors ($mode)..."
  if matugen image "$img" -m "$mode" >/dev/null 2>&1; then
    return 0
  else
    log "Matugen failed. Check if image is valid."
    return 1
  fi
}

reload_ui() {
  log "Reloading UI components..."

  # Reload waybar
  if [[ -f "$HOME/cloudyy_scripts/restart_waybar.sh" ]]; then
    "$HOME/cloudyy_scripts/restart_waybar.sh" >/dev/null 2>&1 &
  else
    pkill waybar 2>/dev/null || true
    sleep 0.1
    waybar &
    disown
  fi

  # Reload kitty (staggered to avoid lag)
  sleep 0.2
  pkill -SIGUSR1 kitty 2>/dev/null || true

  # Reload thunar (file manager) - try multiple approaches
  sleep 0.1
  if pgrep -x thunar >/dev/null; then
    # If thunar is running, restart it
    thunar -q 2>/dev/null || true
    sleep 0.3
    thunar --daemon 2>/dev/null &
    disown
  fi

  # Reload swaync
  sleep 0.2
  swaync-client -R 2>/dev/null || true
  swaync-client -rs 2>/dev/null || true
}

toggle_mode() {
  local img="$1"
  local new_mode="$2"

  # Resolve full path
  img="$(realpath "$img")"
  [[ -f "$img" ]] || die "Image file missing: $img"

  local img_name="${img##*/}"
  log "Switching to $new_mode mode (keeping wallpaper: $img_name)"

  # Regenerate colors in new mode
  if ! generate_colors "$img" "$new_mode"; then
    die "Color generation failed"
  fi

  # Save state
  CURRENT_WALL="$img"
  THEME_MODE="$new_mode"
  save_state

  # Reload UI (no wallpaper animation)
  reload_ui

  notify "Theme switched to $new_mode mode"
}

apply_wallpaper() {
  local img="$1"
  local mode="${2:-$THEME_MODE}"
  local mode_changed="${3:-0}" # Flag to track if mode actually changed

  # Resolve full path
  img="$(realpath "$img")"

  [[ -f "$img" ]] || die "Image file missing: $img"

  ensure_swww

  local img_name="${img##*/}"
  log "Setting wallpaper: $img_name ($mode)"

  # Generate colors first (before wallpaper animation for smoother transition)
  if ! generate_colors "$img" "$mode"; then
    die "Color generation failed"
  fi

  # Save state
  CURRENT_WALL="$img"
  THEME_MODE="$mode"
  save_state

  # Apply wallpaper with transition
  swww img "$img" --transition-type grow --transition-duration 2 --transition-fps 60

  # Wait for animation to complete before reloading UI
  sleep 2.2

  # Reload UI components (staggered to prevent lag)
  reload_ui

  # Smart notifications
  if [[ "$mode_changed" == "1" ]]; then
    notify "Theme switched to $mode mode"
  else
    notify "Wallpaper updated" low
  fi
}

# --- COMMANDS ---

cmd_toggle() {
  read_state

  # Flip Mode
  local new_mode="light"
  [[ "$THEME_MODE" == "light" ]] && new_mode="dark"

  log "Toggling to $new_mode..."

  # Check if current wallpaper actually exists
  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    toggle_mode "$CURRENT_WALL" "$new_mode"
  else
    log "Current wallpaper invalid. Picking random..."
    cmd_random "$new_mode"
  fi
}

cmd_random() {
  local force_mode="${1:-}"

  read_state

  local old_mode="$THEME_MODE"

  # Use current theme mode if not specified
  [[ -z "$force_mode" ]] && force_mode="$THEME_MODE"

  get_wallpapers # Populates global $walls array

  local rand_wall="${walls[RANDOM % ${#walls[@]}]}"

  # Check if mode changed
  local mode_changed=0
  [[ "$old_mode" != "$force_mode" ]] && mode_changed=1

  apply_wallpaper "$rand_wall" "$force_mode" "$mode_changed"
}

cmd_next() {
  read_state
  get_wallpapers

  local next_index=0

  # Find current index
  if [[ -n "$CURRENT_WALL" ]]; then
    for i in "${!walls[@]}"; do
      if [[ "${walls[$i]}" == "$CURRENT_WALL" ]]; then
        next_index=$((i + 1))
        break
      fi
    done
  fi

  # Wrap around
  if ((next_index >= ${#walls[@]})); then
    next_index=0
  fi

  apply_wallpaper "${walls[$next_index]}" "$THEME_MODE" 0 # 0 = mode didn't change
}

cmd_set_image() {
  local img="${1:-}"

  [[ -z "$img" ]] && die "No image specified"
  [[ ! -f "$img" ]] && die "Image not found: $img"

  read_state

  apply_wallpaper "$img" "$THEME_MODE" 0 # 0 = mode didn't change
}

# --- MAIN ---

[[ ! -d "$STATE_DIR" ]] && mkdir -p "$STATE_DIR"

case "${1:-}" in
toggle)
  cmd_toggle
  ;;
random)
  cmd_random "${2:-}"
  ;;
next)
  cmd_next
  ;;
set-image)
  cmd_set_image "${2:-}"
  ;;
refresh)
  read_state
  if [[ -f "$CURRENT_WALL" ]]; then
    apply_wallpaper "$CURRENT_WALL" "$THEME_MODE" 0
  else
    cmd_random
  fi
  ;;
debug)
  DEBUG=1
  log "=== DEBUG MODE ==="
  log "WALL_DIR: $WALL_DIR (expanded: ${WALL_DIR/#\~/$HOME})"
  log "Directory exists: $([ -d "${WALL_DIR/#\~/$HOME}" ] && echo 'YES' || echo 'NO')"
  log "Directory readable: $([ -r "${WALL_DIR/#\~/$HOME}" ] && echo 'YES' || echo 'NO')"
  get_wallpapers
  log "Total wallpapers found: ${#walls[@]}"
  ;;
*)
  echo "Usage: $0 {toggle|random|next|set-image <path>|refresh|debug}"
  echo ""
  echo "Commands:"
  echo "  toggle       - Switch between light/dark mode with current wallpaper"
  echo "  random       - Set random wallpaper"
  echo "  next         - Cycle to next wallpaper"
  echo "  set-image    - Set specific wallpaper by path"
  echo "  refresh      - Reapply current wallpaper and theme"
  echo "  debug        - Show diagnostic information"
  ;;
esac
