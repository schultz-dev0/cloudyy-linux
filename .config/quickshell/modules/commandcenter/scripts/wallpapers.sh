#!/usr/bin/env bash
# List wallpapers with thumbnails for the Wallpaper Picker.
set -euo pipefail

home="${HOME:-$(printf '%s' ~)}"
base="${home}/Wallpapers"
user_base="${base}/user_wallpapers"
state_file="${home}/.config/hypr/theme_state/state.conf"
cache_dir="${home}/.cache/rofi_thumbs"
thumb_size=150
max_jobs=$(nproc 2>/dev/null || echo 4)

mkdir -p "$cache_dir"

CACHE_DIR="$cache_dir"
THUMB_SIZE="$thumb_size"
HOME="$home"
# shellcheck source=../../../../cloudyy_scripts/quickshell/lib/thumb_cache.sh
source "${home}/cloudyy_scripts/quickshell/lib/thumb_cache.sh"
export -f gen_thumb
export CACHE_DIR THUMB_SIZE HOME

mode="dark"
current=""
if [[ -f "$state_file" ]]; then
  raw_mode=$(grep -m1 '^THEME_MODE=' "$state_file" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'[:space:]')
  [[ "$raw_mode" == "light" ]] && mode="light"
  current=$(grep -m1 '^CURRENT_WALL=' "$state_file" 2>/dev/null | cut -d= -f2- | tr -d '"')
fi
if [[ -z "$current" || ! -f "$current" ]]; then
  fallback="${home}/.config/hypr/theme_state/current_wallpaper/current.jpg"
  [[ -f "$fallback" ]] && current="$fallback"
fi
current_real=""
[[ -n "$current" ]] && current_real=$(realpath "$current" 2>/dev/null || echo "$current")

mode_dir="${base}/${mode^}"
dirs=()
[[ -d "$mode_dir" ]] && dirs+=("$mode_dir")
user_mode="${user_base}/${mode^}"
[[ -d "$user_mode" ]] && dirs+=("$user_mode")
[[ ${#dirs[@]} -eq 0 ]] && dirs+=("$base")

catalog_cache="${cache_dir}/picker_catalog_${mode}.json"
sig_cache="${cache_dir}/picker_catalog_${mode}.sig"

# Fast pre-check: skip expensive scan if no wallpaper file/dir is newer than the catalog.
# Each realpath call is a subprocess (~4ms × 258 files = 1s+), so this saves most of that.
if [[ -f "$catalog_cache" && -f "$sig_cache" ]]; then
  stale=0
  for dir in "${dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    if [[ -n "$(find -L "$dir" -maxdepth 3 \( -type f -o -type d \) -newer "$catalog_cache" -print -quit 2>/dev/null)" ]]; then
      stale=1
      break
    fi
  done
  if (( stale == 0 )); then
    jq -c --arg current "$current_real" '.current = $current' "$catalog_cache"
    exit 0
  fi
fi

compute_signature() {
  if [[ ! -s "$1" ]]; then
    printf 'empty'
    return 0
  fi
  while IFS= read -r -d '' entry; do
    printf '%s\n' "${entry#*|}"
  done <"$1" | sort -u | md5sum | awk '{print $1}'
}

tmp_list="$(mktemp)"
trap 'rm -f "$tmp_list"' EXIT

declare -A seen=()
for dir in "${dirs[@]}"; do
  while IFS= read -r -d '' img; do
    real=$(canonical_real "$img")
    [[ -n "${seen[$real]:-}" ]] && continue
    seen[$real]=1
    name=$(basename "$img")
    parent=$(basename "$(dirname "$img")")
    label="$name"
    [[ "$parent" != "$(basename "$dir")" && "$parent" != "Wallpapers" ]] && label="${name} (${parent})"
    printf '%s|%s\0' "$label" "$real" >>"$tmp_list"
  done < <(find -L "$dir" -maxdepth 3 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -print0 2>/dev/null | sort -z)
done

new_sig="$(compute_signature "$tmp_list")"

if [[ -f "$catalog_cache" && -f "$sig_cache" && "$(cat "$sig_cache")" == "$new_sig" ]]; then
  jq -c --arg current "$current_real" '.current = $current' "$catalog_cache"
  exit 0
fi

json_items=()
while IFS= read -r -d '' entry; do
  label="${entry%%|*}"
  real="${entry#*|}"
  thumb=$(gen_thumb "$real")
  [[ -z "$thumb" ]] && thumb="$real"
  esc_label=$(printf '%s' "$label" | jq -Rs .)
  esc_path=$(printf '%s' "$real" | jq -Rs .)
  esc_thumb=$(printf '%s' "$thumb" | jq -Rs .)
  json_items+=("$(printf '{"label":%s,"path":%s,"thumb":%s}' "$esc_label" "$esc_path" "$esc_thumb")")
done <"$tmp_list"

if [[ ${#json_items[@]} -eq 0 ]]; then
  out=$(jq -cn \
    --arg mode "$mode" \
    --arg current "$current_real" \
    '{mode: $mode, current: $current, wallpapers: []}')
  printf '%s\n' "$out"
  printf '%s' "$new_sig" >"$sig_cache"
  printf '%s\n' "$out" >"$catalog_cache"
  exit 0
fi

items_json=$(printf '%s\n' "${json_items[@]}" | jq -s .)
out=$(jq -cn \
  --arg mode "$mode" \
  --arg current "$current_real" \
  --argjson wallpapers "$items_json" \
  '{mode: $mode, current: $current, wallpapers: $wallpapers}')

printf '%s\n' "$out"
printf '%s' "$new_sig" >"$sig_cache"
printf '%s\n' "$out" >"$catalog_cache"
