#!/usr/bin/env bash
# =============================================================================
# appearance.sh — Theme, Wallpaper & Color Profile Menu
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# =============================================================================
# WALLPAPER THUMBNAIL HELPER
# =============================================================================

gen_thumb() {
  local img="$1"
  # Use a hash of the full path to avoid collisions between identically named files in different dirs
  local hash
  hash=$(echo -n "$img" | md5sum | cut -d' ' -f1)
  local thumb="${CACHE_DIR}/${hash}.png"
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

# =============================================================================
# WALLPAPER SELECTOR
# =============================================================================

select_wallpaper() {
  local CURRENT_MODE DISPLAY_MODE
  CURRENT_MODE=$(get_current_mode)
  DISPLAY_MODE="$(tr '[:lower:]' '[:upper:]' <<<"${CURRENT_MODE:0:1}")${CURRENT_MODE:1}"

  local mode_dir="${BASE_WALL_DIR}/${DISPLAY_MODE}"
  local user_mode_dir="${USER_WALL_DIR}/${DISPLAY_MODE}"
  local find_args=()
  local search_dirs=()

  if [[ -d "$mode_dir" && -r "$mode_dir" ]]; then
    search_dirs+=("$mode_dir")
    [[ -d "$user_mode_dir" && -r "$user_mode_dir" ]] && search_dirs+=("$user_mode_dir")
    log "Searching wallpapers in: ${search_dirs[*]}"
  else
    search_dirs+=("$BASE_WALL_DIR")
    find_args+=(-maxdepth 1)
    log "Searching wallpapers in base dir (fallback): $BASE_WALL_DIR"
  fi

  local dir
  for dir in "${search_dirs[@]}"; do
    [[ -d "$dir" && -r "$dir" ]] || {
      notify-send "Error" "Cannot access: $dir"
      return 1
    }
  done

  # Generate thumbnails in parallel
  for dir in "${search_dirs[@]}"; do
    find -L "$dir" "${find_args[@]}" -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
      -print0 2>/dev/null
  done | sort -z | xargs -0 -P "$MAX_JOBS" -I {} bash -c 'gen_thumb "$@"' _ {}

  declare -A wallpaper_paths seen_realpaths
  >"$TEMP_INPUT"

  while IFS= read -r -d '' img; do
    local real_img
    real_img="$(realpath "$img" 2>/dev/null || echo "$img")"
    [[ -n "${seen_realpaths[$real_img]:-}" ]] && continue
    seen_realpaths[$real_img]=1

    local basename_img
    basename_img="$(basename "$img")"
    local hash
    hash=$(echo -n "$img" | md5sum | cut -d' ' -f1)
    local thumb="${CACHE_DIR}/${hash}.png"

    if [[ -f "$thumb" ]]; then
      local display_name="$basename_img"
      if [[ -n "${wallpaper_paths[$display_name]:-}" ]]; then
         display_name="${display_name} ($(basename "$(dirname "$img")"))"
      fi

      echo -en "${display_name}\0icon\x1f${thumb}\n" >>"$TEMP_INPUT"
      wallpaper_paths["$display_name"]="$img"
    fi
  done < <(
    for dir in "${search_dirs[@]}"; do
      find -L "$dir" "${find_args[@]}" -type f \
        \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
        -print0 2>/dev/null
    done | sort -z
  )

  [[ ! -s "$TEMP_INPUT" ]] && {
    notify-send "No Wallpapers" "No images found in ${search_dirs[*]}"
    return 1
  }

  local selection
  selection=$(
    rofi -dmenu -i -p "Select Wallpaper" \
      -theme-str 'window { width: 60%; }' \
      -theme-str 'listview { columns: 4; lines: 3; flow: horizontal; }' \
      -theme-str 'element { orientation: vertical; padding: 20px; spacing: 10px; children: [ element-icon ]; }' \
      -theme-str 'element-icon { size: 150px; horizontal-align: 0.5; }' \
      -show-icons <"$TEMP_INPUT"
  )

  if [[ -n "$selection" && -n "${wallpaper_paths[$selection]:-}" ]]; then
    run_app "$THEME_CTL" set-image "${wallpaper_paths[$selection]}"
  elif [[ -n "$selection" ]]; then
    notify-send "Error" "Could not find path for: $selection"
    return 1
  fi
}

# =============================================================================
# COLOR PROFILE MENU
# =============================================================================

show_color_menu() {
  local choice
  choice=$(menu "Color Scheme" \
    "Tonal Spot  — balanced, subtle (default)\nVibrant     — punchy, boosted saturation\nExpressive  — bold hue shifts\nNeutral     — muted, desaturated\nMonochrome  — full greyscale\nFidelity    — faithful to wallpaper\nContent     — conservative, readable\nRainbow     — full spectrum\nFruit Salad — inverted spectrum")

  local variant=""
  case "$choice" in
  "Tonal Spot"*) variant="tonal_spot" ;;
  "Vibrant"*) variant="vibrant" ;;
  "Expressive"*) variant="expressive" ;;
  "Neutral"*) variant="neutral" ;;
  "Monochrome"*) variant="monochrome" ;;
  "Fidelity"*) variant="fidelity" ;;
  "Content"*) variant="content" ;;
  "Rainbow"*) variant="rainbow" ;;
  "Fruit Salad"*) variant="fruit_salad" ;;
  *)
    show_appearance_menu
    return
    ;;
  esac

  show_contrast_menu "$variant"
}

show_contrast_menu() {
  local variant="$1"
  local variant_label
  variant_label="${variant//_/ }"
  variant_label="$(tr '[:lower:]' '[:upper:]' <<<"${variant_label:0:1}")${variant_label:1}"

  local choice
  choice=$(menu "Contrast — ${variant_label}" \
    "-1.0  Softest\n-0.5  Softer\n+0.0  Default\n+0.5  Sharper\n+1.0  Sharpest")

  local contrast=""
  case "$choice" in
  "-1.0"*) contrast="-1.0" ;;
  "-0.5"*) contrast="-0.5" ;;
  "+0.0"*) contrast="0.0" ;;
  "+0.5"*) contrast="0.5" ;;
  "+1.0"*) contrast="1.0" ;;
  *)
    show_color_menu
    return
    ;;
  esac

  notify-send "Theme" "Applying ${variant_label} contrast ${contrast}..." -t 2000
  run_app "$THEME_CTL" refresh "scheme-${variant}" "$contrast"
}

# =============================================================================
# APPEARANCE MENU
# =============================================================================

show_appearance_menu() {
  local CURRENT_MODE DISPLAY_MODE
  CURRENT_MODE=$(get_current_mode)
  DISPLAY_MODE="$(tr '[:lower:]' '[:upper:]' <<<"${CURRENT_MODE:0:1}")${CURRENT_MODE:1}"

  local choice
  choice=$(menu "Theme: $DISPLAY_MODE" \
    "󰔎 Toggle Mode\n󰸉 Select Wallpaper\n󰑕 Next Wallpaper\n󰎨 Color Profile\n󰔄 Theme Cycle")

  case "$choice" in
  *"Toggle Mode"*)
    run_app "$THEME_CTL" toggle
    notify-send "Theme" "Switching theme mode..." -t 2000
    ;;
  *"Select Wallpaper"*)
    select_wallpaper
    ;;
  *"Next Wallpaper"*)
    run_app "$THEME_CTL" next
    notify-send "Theme" "Loading next wallpaper..." -t 2000
    ;;
  *"Color Profile"*)
    show_color_menu
    ;;
  *"Theme Cycle"*)
    exec "${ROFI_DIR}/cycle.sh"
    ;;
  *) back_to_main ;;
  esac
}

# =============================================================================
# ENTRY POINT
# =============================================================================

init_dirs

case "${1:-}" in
--select) select_wallpaper ;;
*) show_appearance_menu ;;
esac
