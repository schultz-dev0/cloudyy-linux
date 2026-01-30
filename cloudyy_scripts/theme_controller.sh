#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG ---
readonly WALLPAPER_DIR="${HOME}/Wallpapers"
readonly STATE_FILE="${HOME}/.config/hypr/theme_state/state.conf"
readonly TEMP_DIR="${XDG_RUNTIME_DIR:-/tmp}/wallpaper_tmp"
readonly CACHE_IMAGE="${TEMP_DIR}/current_wallpaper.png"

# --- UTILS ---
die() {
  notify-send "Wallpaper Error" "$*" >&2
  exit 1
}

# --- CORE LOGIC ---
ensure_swww() {
  if ! pgrep -x swww-daemon >/dev/null 2>&1; then
    swww-daemon --format xrgb &
    disown
    sleep 0.5
  fi
}

extract_first_frame() {
  local input="$1"
  local output="$2"

  # Create temp directory if it doesn't exist
  mkdir -p "$(dirname "$output")"

  # Extract first frame based on file type
  local mime=$(file --mime-type -b "$input")

  if [[ "$mime" == *"image/gif"* ]]; then
    # Extract first frame from GIF
    magick "${input}[0]" "$output" 2>/dev/null ||
      ffmpeg -i "$input" -vframes 1 "$output" -y 2>/dev/null ||
      return 1
  elif [[ "$mime" == *"video/"* ]]; then
    # Extract first frame from video
    ffmpeg -i "$input" -vframes 1 "$output" -y 2>/dev/null || return 1
  else
    return 1
  fi

  return 0
}

generate_colors() {
  local img="$1"
  local mime=$(file --mime-type -b "$img")
  local ext="${img##*.}"
  ext="${ext,,}"

  # For animated content, extract first frame and generate colors from it
  if [[ "$ext" == "gif" || "$ext" == "mp4" || "$mime" == *"video"* || "$mime" == *"image/gif"* ]]; then
    mkdir -p "$TEMP_DIR"
    local temp_frame="${TEMP_DIR}/first_frame.png"

    if extract_first_frame "$img" "$temp_frame"; then
      matugen image "$temp_frame" >/dev/null 2>&1 || true
      rm -f "$temp_frame"
    else
      # Fallback to matugen's built-in frame extraction
      matugen image "${img}[0]" >/dev/null 2>&1 || true
    fi
  else
    matugen image "$img" >/dev/null 2>&1 || true
  fi

  # Reload Waybar to apply new colors
  pkill -SIGUSR2 waybar 2>/dev/null || true
}

cache_current_wallpaper() {
  # Cache the current wallpaper to prevent flash to default background
  mkdir -p "$TEMP_DIR"

  # Try to get current swww image
  if pgrep -x swww-daemon >/dev/null 2>&1; then
    # Query swww for current image
    local current_img=$(swww query 2>/dev/null | grep -oP 'image: \K.*' | head -n1)

    if [[ -n "$current_img" && -f "$current_img" ]]; then
      cp "$current_img" "$CACHE_IMAGE" 2>/dev/null || true
    fi
  fi
}

apply_wallpaper() {
  local img="$1"

  [[ -f "$img" ]] || die "File not found: $img"

  # Detect file type
  local mime=$(file --mime-type -b "$img")
  local ext="${img##*.}"
  ext="${ext,,}"

  # Generate color scheme
  generate_colors "$img"

  # Determine if animated
  if [[ "$mime" == *"image/gif"* || "$mime" == *"video/"* || "$ext" == "gif" || "$ext" == "mp4" ]]; then
    # === ANIMATION MODE ===

    # Cache current wallpaper before killing swww
    cache_current_wallpaper

    # Set a static first frame with swww before switching to mpvpaper
    mkdir -p "$TEMP_DIR"
    local transition_frame="${TEMP_DIR}/transition_frame.png"

    if extract_first_frame "$img" "$transition_frame"; then
      ensure_swww
      swww img "$transition_frame" --transition-type none --transition-duration 0 2>/dev/null || true
      sleep 0.1
    elif [[ -f "$CACHE_IMAGE" ]]; then
      # Use cached image if frame extraction fails
      ensure_swww
      swww img "$CACHE_IMAGE" --transition-type none --transition-duration 0 2>/dev/null || true
      sleep 0.1
    fi

    # Now kill swww and mpvpaper
    pkill -9 mpvpaper 2>/dev/null || true
    swww clear 2>/dev/null || true
    pkill -9 swww-daemon 2>/dev/null || true
    sleep 0.2

    # Launch mpvpaper with proper scaling and performance settings
    mpvpaper -o "no-audio loop-playlist hwdec=auto video-sync=display-resample interpolation scale=ewa_lanczossharp cscale=ewa_lanczossharp panscan=1.0" '*' "$img" >/dev/null 2>&1 &
    disown

    # Clean up transition frame
    rm -f "$transition_frame"
  else
    # === STATIC MODE ===

    pkill -9 mpvpaper 2>/dev/null || true
    ensure_swww

    # Random transition effect
    local trans_types=("grow" "outer" "wipe" "wave" "random")
    local rand_type="${trans_types[RANDOM % ${#trans_types[@]}]}"

    swww img "$img" \
      --transition-type "$rand_type" \
      --transition-pos "0.5,0.5" \
      --transition-duration 1.5 \
      --transition-fps 60
  fi
}

# --- HANDLERS ---
cmd_set_image() {
  local img="$1"
  [[ "$img" != /* ]] && img="$(realpath "$img")"
  apply_wallpaper "$img"
}

cmd_random() {
  shopt -s nullglob nocaseglob globstar
  local walls=("$WALLPAPER_DIR"/**/*.{jpg,jpeg,png,gif,mp4,webp})
  shopt -u nullglob nocaseglob globstar

  [[ ${#walls[@]} -eq 0 ]] && die "No wallpapers found in $WALLPAPER_DIR"

  local rand_wall="${walls[RANDOM % ${#walls[@]}]}"
  cmd_set_image "$rand_wall"
}

# --- MAIN ---
case "${1:-}" in
set-image)
  [[ -z "${2:-}" ]] && die "Usage: $0 set-image <path>"
  cmd_set_image "$2"
  ;;
random)
  cmd_random
  ;;
*)
  echo "Usage: $0 {set-image <path>|random}"
  exit 1
  ;;
esac
