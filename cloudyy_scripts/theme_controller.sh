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
readonly DARK_LAST="${STATE_DIR}/dark_last"
readonly LIGHT_LAST="${STATE_DIR}/light_last"

WALLPAPER_CMD=()
WALLPAPER_DAEMON_CMD=()

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
  # Persist per-mode last wallpaper for toggle memory
  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    [[ "$THEME_MODE" == "light" ]] && echo "$CURRENT_WALL" >"$LIGHT_LAST" || echo "$CURRENT_WALL" >"$DARK_LAST"
  fi
}

# --- HELPERS ---

get_wallpapers() {
  walls=()
  local base_dir="${WALL_DIR/#\~/$HOME}"
  [[ -d "$base_dir" ]] || die "Wallpaper directory not found: $base_dir"
  [[ -r "$base_dir" ]] || die "Wallpaper directory not readable: $base_dir"

  # Use mode-specific subdir (Dark/Light) if it exists, mirroring rofi's behaviour.
  # Capitalise first letter to match the dir naming convention.
  local mode_cap="${THEME_MODE^}"
  local mode_dir="${base_dir}/${mode_cap}"
  local wall_dir="$base_dir"
  local depth_args=()
  if [[ -d "$mode_dir" && -r "$mode_dir" ]]; then
    wall_dir="$mode_dir"
  else
    # In the flat base dir, stay shallow so Dark/ and Light/ subdirs aren't
    # accidentally included in the scan.
    depth_args=(-maxdepth 1)
  fi

  mapfile -d '' walls < <(find -L "$wall_dir" "${depth_args[@]}" -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
    -print0 2>/dev/null | sort -z)
  ((${#walls[@]} > 0)) || die "No wallpapers found in $wall_dir"
  log "Found ${#walls[@]} wallpaper(s) [$(basename "$wall_dir")]"
}

ensure_swww() {
  if ((${#WALLPAPER_CMD[@]} == 0)); then
    if command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1; then
      WALLPAPER_CMD=(awww)
      WALLPAPER_DAEMON_CMD=(awww-daemon)
    elif command -v swww >/dev/null 2>&1 && command -v swww-daemon >/dev/null 2>&1; then
      WALLPAPER_CMD=(swww)
      WALLPAPER_DAEMON_CMD=(swww-daemon)
    else
      die "No supported wallpaper backend found (need awww or swww)"
    fi
  fi

  pgrep -x "${WALLPAPER_DAEMON_CMD[0]}" >/dev/null && return 0
  log "Starting ${WALLPAPER_DAEMON_CMD[0]}..."
  "${WALLPAPER_DAEMON_CMD[@]}" --format xrgb >/dev/null 2>&1 &
  sleep 1
}

pick_transition() {
  # Keep a conservative allowlist of transitions known to work well.
  local transitions=(simple grow center outer wipe wave any)
  echo "${transitions[RANDOM % ${#transitions[@]}]}"
}

run_matugen() {
  local img="$1" mode="$2"
  local variant="${3:-}" contrast="${4:-}"
  local extra_args=()

  [[ -n "$variant" ]] && extra_args+=(--type "$variant")
  [[ -n "$contrast" ]] && extra_args+=(--contrast "$contrast")

  log "Running matugen ($mode${variant:+ $variant}${contrast:+ contrast $contrast})..."
  matugen image "$img" -m "$mode" --source-color-index 0 "${extra_args[@]}" || {
    log "matugen failed — check image validity"
    return 1
  }
}

sync_current_wallpaper() {
  local img="$1"
  local transition="${2:-$(pick_transition)}"
  [[ -f "$img" ]] || return 0

  ensure_swww
  "${WALLPAPER_CMD[@]}" img "$img" \
    --transition-type "$transition" \
    --transition-duration 1 \
    --transition-fps 60
}

# --- COMMANDS ---

cmd_apply() {
  local img="$1"
  local mode="${2:-$THEME_MODE}"
  local transition="${3:-$(pick_transition)}"

  img="$(realpath "$img")"
  [[ -f "$img" ]] || die "Image not found: $img"

  ensure_swww

  log "Applying: $(basename "$img") [$mode]"

  # Generate colors first — post_hooks fire and restart apps
  run_matugen "$img" "$mode" || log "WARNING: Matugen failed, but continuing to wallpaper..."

  # Save state
  CURRENT_WALL="$img"
  THEME_MODE="$mode"
  save_state

  # Animate wallpaper after color generation
  "${WALLPAPER_CMD[@]}" img "$img" \
    --transition-type "$transition" \
    --transition-duration 2 \
    --transition-fps 60

  notify "Wallpaper applied" low
}

cmd_restore() {
  read_state
  local img="$CURRENT_WALL"

  [[ -n "$img" && -f "$img" ]] || img="$CURRENT_WALLPAPER_FILE"

  if [[ -f "$img" ]]; then
    run_matugen "$img" "$THEME_MODE" || log "WARNING: Matugen failed during restore"
    sync_current_wallpaper "$img"
    if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
      save_state
    fi
  else
    log "No saved wallpaper to restore"
  fi
}

cmd_toggle() {
  read_state
  local new_mode="light"
  [[ "$THEME_MODE" == "light" ]] && new_mode="dark"
  log "Toggling → $new_mode"

  # Restore the last wallpaper that was active in the target mode.
  local last_file
  [[ "$new_mode" == "light" ]] && last_file="$LIGHT_LAST" || last_file="$DARK_LAST"
  local last_wall=""
  [[ -f "$last_file" ]] && last_wall="$(tr -d '[:space:]' <"$last_file")"

  if [[ -n "$last_wall" && -f "$last_wall" ]]; then
    log "Restoring $(basename "$last_wall") [$new_mode]"
    cmd_apply "$last_wall" "$new_mode"
  elif [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    run_matugen "$CURRENT_WALL" "$new_mode"
    sync_current_wallpaper "$CURRENT_WALL"
    THEME_MODE="$new_mode"
    save_state
    notify "Switched to $new_mode mode"
  else
    log "No wallpaper history — picking random"
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
    # Resolve both sides so symlinks in Dark/Light dirs match their realpath targets.
    local current_real
    current_real="$(realpath "$CURRENT_WALL" 2>/dev/null || echo "$CURRENT_WALL")"
    for i in "${!walls[@]}"; do
      local wall_real
      wall_real="$(realpath "${walls[$i]}" 2>/dev/null || echo "${walls[$i]}")"
      [[ "$wall_real" == "$current_real" ]] && {
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
    sync_current_wallpaper "$CURRENT_WALL"
    save_state
    notify "Theme refreshed" low
  else
    cmd_random
  fi
}

cmd_tag() {
  local img="${1:-}" mode="${2:-}"
  [[ -z "$img" || -z "$mode" ]] && die "Usage: tag <image> <dark|light>"
  [[ "$mode" != "dark" && "$mode" != "light" ]] && die "Mode must be 'dark' or 'light'"
  [[ -f "$img" ]] || die "Image not found: $img"
  img="$(realpath "$img")"
  local mode_dir="${WALL_DIR}/${mode^}"
  mkdir -p "$mode_dir"
  ln -sf "$img" "${mode_dir}/$(basename "$img")"
  log "Tagged '$(basename "$img")' → $mode ($mode_dir)"
}

cmd_untag() {
  local img="${1:-}" mode="${2:-}"
  [[ -z "$img" || -z "$mode" ]] && die "Usage: untag <image> <dark|light>"
  [[ "$mode" != "dark" && "$mode" != "light" ]] && die "Mode must be 'dark' or 'light'"
  local mode_dir="${WALL_DIR}/${mode^}"
  local link="${mode_dir}/$(basename "$img")"
  [[ -L "$link" ]] || die "No tag found for '$(basename "$img")' in $mode"
  rm "$link"
  log "Untagged '$(basename "$img")' from $mode"
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
    sync_current_wallpaper "$CURRENT_WALL"
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
restore) cmd_restore ;;
refresh) cmd_refresh "${2:-}" "${3:-}" ;;
set)
  shift
  cmd_set "$@"
  ;;
get-mode)
  read_state
  echo "$THEME_MODE"
  ;;
tag) cmd_tag "${2:-}" "${3:-}" ;;
untag) cmd_untag "${2:-}" "${3:-}" ;;
debug)
  read_state
  log "WALL_DIR: $WALL_DIR"
  log "THEME_MODE: $THEME_MODE"
  log "CURRENT_WALL: $CURRENT_WALL"
  log "DARK_LAST:  $(cat "$DARK_LAST" 2>/dev/null || echo '(none)')"
  log "LIGHT_LAST: $(cat "$LIGHT_LAST" 2>/dev/null || echo '(none)')"
  log "Dark dir:  $([ -d "${WALL_DIR}/Dark" ] && echo YES || echo NO)"
  log "Light dir: $([ -d "${WALL_DIR}/Light" ] && echo YES || echo NO)"
  get_wallpapers
  log "Wallpapers in current mode pool: ${#walls[@]}"
  ;;
*)
  cat <<EOF
Usage: $(basename "$0") {toggle|random|next|set-image <path>|restore|refresh|set|get-mode|tag|untag|debug}

  toggle            Switch dark/light mode, restoring last wallpaper for that mode
  random            Random wallpaper from current mode's pool
  next              Next wallpaper alphabetically in current mode's pool
  set-image <path>  Apply a specific wallpaper
  restore           Restore the last saved wallpaper and theme without notifications
  refresh           Re-run matugen on current wallpaper
  set               Set specific parameters (e.g., --mode light)
  get-mode          Print current mode (dark/light) — used by rofi/waybar
  tag <img> <mode>  Symlink a wallpaper into Dark/ or Light/ pool
  untag <img> <mode> Remove a wallpaper's symlink from a mode pool
  debug             Show diagnostic info

Mode pools: ~/Wallpapers/Dark/  ~/Wallpapers/Light/
  Create symlinks here pointing to wallpapers you want for each mode.
  When a pool dir is absent, falls back to all of ~/Wallpapers/ (current behaviour).
EOF
  ;;
esac
