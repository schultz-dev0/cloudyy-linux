#!/usr/bin/env bash
# ==============================================================================
# THEME CONTROLLER
# Manages wallpaper + matugen. All app restarts are handled by matugen
# post_hooks in config.toml — this script does not touch running processes.
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION ---
readonly WALL_DIR="${HOME}/Wallpapers"
readonly STATE_DIR="${HOME}/.config/hypr/theme_state"
readonly STATE_FILE="${STATE_DIR}/state.conf"
readonly PUBLIC_STATE="${STATE_DIR}/state"
readonly CURRENT_WALLPAPER_DIR="${STATE_DIR}/current_wallpaper"
readonly CURRENT_WALLPAPER_FILE="${CURRENT_WALLPAPER_DIR}/current.jpg"

# --- LOGGING ---
log() { printf '\033[1;34m[THEME]\033[0m %s\n' "$*" >&2; }
notify() { notify-send "Theme Controller" "$1" -u "${2:-normal}" -t 3000 2>/dev/null || true; }
die() {
  log "ERROR: $*"
  notify "Error: $*" critical
  exit 1
}

# --- STATE ---

read_state() {
  THEME_MODE="dark"
  CURRENT_WALL=""
  [[ -f "$STATE_FILE" ]] || return 0
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ $key =~ ^# ]] && continue
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
    THEME_MODE) THEME_MODE="$value" ;;
    CURRENT_WALL) CURRENT_WALL="$value" ;;
    esac
  done <"$STATE_FILE"
}

save_state() {
  mkdir -p "$STATE_DIR" "$CURRENT_WALLPAPER_DIR"
  cat >"$STATE_FILE" <<EOF
THEME_MODE="$THEME_MODE"
CURRENT_WALL="$CURRENT_WALL"
EOF
  echo "$([[ "$THEME_MODE" == "light" ]] && echo 1 || echo 0)" >"$PUBLIC_STATE"
  [[ -f "$CURRENT_WALL" ]] && cp "$CURRENT_WALL" "$CURRENT_WALLPAPER_FILE"
}

# --- HELPERS ---

get_wallpapers() {
  walls=()
  local wall_dir="${WALL_DIR/#\~/$HOME}"
  [[ -d "$wall_dir" ]] || die "Wallpaper directory not found: $wall_dir"
  [[ -r "$wall_dir" ]] || die "Wallpaper directory not readable: $wall_dir"
  mapfile -d '' walls < <(find -L "$wall_dir" -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0 2>/dev/null | sort -z)
  ((${#walls[@]} > 0)) || die "No wallpapers found in $wall_dir"
  log "Found ${#walls[@]} wallpaper(s)"
}

ensure_swww() {
  pgrep -x swww-daemon >/dev/null && return 0
  log "Starting swww-daemon..."
  swww-daemon --format xrgb >/dev/null 2>&1 &
  sleep 1
}

run_matugen() {
  local img="$1" mode="$2"
  local variant="${3:-}" contrast="${4:-}"
  local extra_args=()

  [[ -n "$variant" ]] && extra_args+=(--type "$variant")
  [[ -n "$contrast" ]] && extra_args+=(--contrast "$contrast")

  log "Running matugen ($mode${variant:+ $variant}${contrast:+ contrast $contrast})..."
  matugen image "$img" -m "$mode" "${extra_args[@]}" || {
    log "matugen failed — check image validity"
    return 1
  }
}

# --- COMMANDS ---

cmd_apply() {
  local img="$1"
  local mode="${2:-$THEME_MODE}"
  local transition="${3:-grow}"

  img="$(realpath "$img")"
  [[ -f "$img" ]] || die "Image not found: $img"

  ensure_swww

  log "Applying: $(basename "$img") [$mode]"

  # Generate colors first — post_hooks fire and restart apps
  run_matugen "$img" "$mode"

  # Save state
  CURRENT_WALL="$img"
  THEME_MODE="$mode"
  save_state

  # Animate wallpaper after color generation
  swww img "$img" \
    --transition-type "$transition" \
    --transition-duration 2 \
    --transition-fps 60

  notify "Wallpaper applied" low
}

cmd_toggle() {
  read_state
  local new_mode="light"
  [[ "$THEME_MODE" == "light" ]] && new_mode="dark"
  log "Toggling → $new_mode"

  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    run_matugen "$CURRENT_WALL" "$new_mode"
    THEME_MODE="$new_mode"
    save_state
    notify "Switched to $new_mode mode"
  else
    log "No current wallpaper — picking random"
    cmd_random "$new_mode"
  fi
}

cmd_random() {
  local force_mode="${1:-}"
  read_state
  [[ -z "$force_mode" ]] && force_mode="$THEME_MODE"
  get_wallpapers
  local rand="${walls[RANDOM % ${#walls[@]}]}"
  cmd_apply "$rand" "$force_mode"
}

cmd_next() {
  read_state
  get_wallpapers
  local next=0
  if [[ -n "$CURRENT_WALL" ]]; then
    for i in "${!walls[@]}"; do
      [[ "${walls[$i]}" == "$CURRENT_WALL" ]] && {
        next=$((i + 1))
        break
      }
    done
  fi
  ((next >= ${#walls[@]})) && next=0
  cmd_apply "${walls[$next]}" "$THEME_MODE"
}

cmd_set_image() {
  local img="${1:-}"
  [[ -z "$img" ]] && die "No image specified"
  [[ -f "$img" ]] || die "Image not found: $img"
  read_state
  cmd_apply "$img" "$THEME_MODE"
}

cmd_refresh() {
  local variant="${1:-}" contrast="${2:-}"
  read_state
  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    run_matugen "$CURRENT_WALL" "$THEME_MODE" "$variant" "$contrast"
    save_state
    notify "Theme refreshed" low
  else
    cmd_random
  fi
}

cmd_set() {
  local target_mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --mode)
      target_mode="$2"
      shift 2
      ;;
    *)
      die "Unknown argument: $1"
      ;;
    esac
  done

  [[ -z "$target_mode" ]] && die "Usage: set --mode <light|dark>"
  [[ "$target_mode" != "light" && "$target_mode" != "dark" ]] && die "Invalid mode: $target_mode"

  read_state
  log "Setting mode → $target_mode"

  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    run_matugen "$CURRENT_WALL" "$target_mode"
    THEME_MODE="$target_mode"
    save_state
    notify "Mode set to $target_mode"
  else
    # Update state only if no wallpaper is active
    THEME_MODE="$target_mode"
    save_state
    notify "Mode updated to $target_mode (no active wallpaper)"
  fi
}

# --- INIT ---
[[ ! -d "$STATE_DIR" ]] && mkdir -p "$STATE_DIR"

case "${1:-}" in
toggle) cmd_toggle ;;
random) cmd_random "${2:-}" ;;
next) cmd_next ;;
set-image) cmd_set_image "${2:-}" ;;
refresh) cmd_refresh "${2:-}" "${3:-}" ;;
set)
  shift
  cmd_set "$@"
  ;;
debug)
  read_state
  log "WALL_DIR: $WALL_DIR"
  log "THEME_MODE: $THEME_MODE"
  log "CURRENT_WALL: $CURRENT_WALL"
  log "Dir exists: $([ -d "${WALL_DIR/#\~/$HOME}" ] && echo YES || echo NO)"
  get_wallpapers
  log "Total wallpapers: ${#walls[@]}"
  ;;
*)
  cat <<EOF
Usage: $(basename "$0") {toggle|random|next|set-image <path>|refresh|set|debug}

  toggle        Switch dark/light mode, keep current wallpaper
  random        Random wallpaper in current mode
  next          Next wallpaper alphabetically
  set-image     Apply a specific wallpaper by path
  refresh       Re-run matugen on current wallpaper
  set           Set specific parameters (e.g., --mode light)
  debug         Show diagnostic info
EOF
  ;;
esac
