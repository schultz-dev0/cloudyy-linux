#!/usr/bin/env bash
# ==============================================================================
# THEME CONTROLLER (Fixed Randomizer)
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION ---
readonly WALLPAPER_DIR="${HOME}/Wallpapers"
readonly STATE_DIR="${HOME}/.config/hypr/theme_state"
readonly STATE_FILE="${STATE_DIR}/state.conf"

# DEFAULTS
readonly DEFAULT_TYPE="scheme-tonal-spot"
readonly DEFAULT_CONTRAST="0"

# --- STATE VARIABLES ---
MATUGEN_TYPE="$DEFAULT_TYPE"
MATUGEN_CONTRAST="$DEFAULT_CONTRAST"

# --- UTILS ---
die() {
  printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2
  exit 1
}

# --- STATE MANAGEMENT ---
read_state() {
  [[ -f "$STATE_FILE" ]] || return 0
  local key value
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ -z "$key" || "${key:0:1}" == "#" ]] && continue
    value="${value#[\"\']}"
    value="${value%[\"\']}"
    case "$key" in
    MATUGEN_TYPE) MATUGEN_TYPE="$value" ;;
    MATUGEN_CONTRAST) MATUGEN_CONTRAST="$value" ;;
    esac
  done <"$STATE_FILE"
}

save_state() {
  [[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
  printf 'MATUGEN_TYPE=%s\nMATUGEN_CONTRAST=%s\n' \
    "$MATUGEN_TYPE" "$MATUGEN_CONTRAST" >"$STATE_FILE"
}

# --- CORE LOGIC ---
ensure_services() {
  if ! pgrep -x swww-daemon >/dev/null; then
    uwsm-app -- swww-daemon --format xrgb &
    disown
    sleep 0.5
  fi
}

generate_colors() {
  local img="$1"
  read_state

  local cmd=(matugen image "$img")
  [[ "$MATUGEN_TYPE" != "disable" ]] && cmd+=(--type "$MATUGEN_TYPE")
  [[ "$MATUGEN_CONTRAST" != "disable" ]] && cmd+=(--contrast "$MATUGEN_CONTRAST")

  "${cmd[@]}" || die "Matugen failed"
  hyprctl reload >/dev/null
}

apply_wallpaper() {
  local img="$1"
  [[ -f "$img" ]] || die "File not found: $img"

  ensure_services
  swww img "$img" --transition-type grow --transition-duration 2 --transition-fps 60
  generate_colors "$img"
}

# --- COMMANDS ---

cmd_random() {
  # 1. Enable case-insensitive matching (Fixes .JPG/.PNG issues)
  shopt -s nullglob nocaseglob

  # 2. Build the array using YOUR explicit logic
  local walls=()

  # Root folder
  walls+=("$WALLPAPER_DIR"/*.jpg)
  walls+=("$WALLPAPER_DIR"/*.jpeg)
  walls+=("$WALLPAPER_DIR"/*.png)
  walls+=("$WALLPAPER_DIR"/*.webp)
  walls+=("$WALLPAPER_DIR"/*.gif)

  # Subfolders (1 level deep)
  walls+=("$WALLPAPER_DIR"/*/*.jpg)
  walls+=("$WALLPAPER_DIR"/*/*.jpeg)
  walls+=("$WALLPAPER_DIR"/*/*.png)
  walls+=("$WALLPAPER_DIR"/*/*.webp)
  walls+=("$WALLPAPER_DIR"/*/*.gif)

  # Disable options to return to normal behavior
  shopt -u nullglob nocaseglob

  # 3. Check if we found anything
  ((${#walls[@]} > 0)) || die "No wallpapers found in $WALLPAPER_DIR"

  # 4. Pick Random
  local random_wall="${walls[RANDOM % ${#walls[@]}]}"
  apply_wallpaper "$random_wall"
}

cmd_set_image() {
  local img="$1"
  [[ "$img" != /* ]] && img="$(pwd)/$img"
  apply_wallpaper "$img"
}

cmd_config() {
  read_state
  local do_refresh=0
  while (($# > 0)); do
    case "$1" in
    --type)
      MATUGEN_TYPE="$2"
      do_refresh=1
      shift 2
      ;;
    --contrast)
      MATUGEN_CONTRAST="$2"
      do_refresh=1
      shift 2
      ;;
    *) die "Unknown option: $1" ;;
    esac
  done
  save_state
  if ((do_refresh)); then
    local current
    current=$(swww query | grep -oP 'image: \K.*' | head -n1) || true
    [[ -f "$current" ]] && generate_colors "$current"
  fi
}

# --- MAIN ---
case "${1:-}" in
set-image)
  shift
  cmd_set_image "${1:-}"
  ;;
random) cmd_random ;;
config)
  shift
  cmd_config "$@"
  ;;
get)
  read_state
  echo "Type: $MATUGEN_TYPE | Contrast: $MATUGEN_CONTRAST"
  ;;
*) die "Usage: $0 {set-image <path>|random|config|get}" ;;
esac
