#!/usr/bin/env bash
# Shared wallpaper thumbnail cache helpers (rofi + Quickshell picker).
# Expects CACHE_DIR, THUMB_SIZE, and HOME to be set by the caller.

path_hash() {
  printf '%s' "$1" | md5sum | awk '{print $1}'
}

canonical_real() {
  realpath "$1" 2>/dev/null || printf '%s' "$1"
}

path_aliases() {
  local real="$1"
  local seen="" alias

  add_alias() {
    local value="$1"
    [[ -z "$value" ]] && return 0
    case "$seen" in *"|$value|"*) return 0 ;; esac
    seen="${seen}|${value}|"
    printf '%s\0' "$value"
  }

  add_alias "$real"

  if [[ "$real" == "${HOME}/cloudyy-linux/Wallpapers/"* ]]; then
    add_alias "${HOME}/Wallpapers/${real#"${HOME}/cloudyy-linux/Wallpapers/"}"
  elif [[ "$real" == "${HOME}/Wallpapers/"* ]]; then
    add_alias "${HOME}/cloudyy-linux/Wallpapers/${real#"${HOME}/Wallpapers/"}"
  fi

  if [[ "$real" == "${HOME}/cloudyy-linux/Wallpapers/user_wallpapers/"* ]]; then
    add_alias "${HOME}/Wallpapers/user_wallpapers/${real#"${HOME}/cloudyy-linux/Wallpapers/user_wallpapers/"}"
  elif [[ "$real" == "${HOME}/Wallpapers/user_wallpapers/"* ]]; then
    add_alias "${HOME}/cloudyy-linux/Wallpapers/user_wallpapers/${real#"${HOME}/Wallpapers/user_wallpapers/"}"
  fi
}

thumb_file_for_path() {
  printf '%s/%s.png' "$CACHE_DIR" "$(path_hash "$1")"
}

find_cached_thumb() {
  local real="$1"
  local src_mtime thumb_mtime alias thumb
  src_mtime=$(stat -c %Y "$real" 2>/dev/null || echo 0)

  while IFS= read -r -d '' alias; do
    thumb="$(thumb_file_for_path "$alias")"
    [[ -f "$thumb" ]] || continue
    thumb_mtime=$(stat -c %Y "$thumb" 2>/dev/null || echo 0)
    if (( thumb_mtime >= src_mtime )); then
      printf '%s' "$thumb"
      return 0
    fi
  done < <(path_aliases "$real")

  return 1
}

promote_thumb() {
  local real="$1"
  local from="$2"
  local canonical
  canonical="$(thumb_file_for_path "$real")"
  [[ "$from" == "$canonical" || -f "$canonical" ]] && return 0
  cp -n "$from" "$canonical" 2>/dev/null || ln -f "$from" "$canonical" 2>/dev/null || true
}

gen_thumb() {
  local img="$1"
  local real hash thumb converter cached canonical
  real=$(canonical_real "$img")
  [[ -f "$real" ]] || return 1

  if cached=$(find_cached_thumb "$real"); then
    promote_thumb "$real" "$cached"
    canonical="$(thumb_file_for_path "$real")"
    if [[ -f "$canonical" ]]; then
      printf '%s' "$canonical"
    else
      printf '%s' "$cached"
    fi
    return 0
  fi

  hash=$(path_hash "$real")
  thumb="${CACHE_DIR}/${hash}.png"
  converter="convert"
  command -v magick &>/dev/null && converter="magick"
  if "$converter" "${real}[0]" -strip \
    -resize "${THUMB_SIZE}x${THUMB_SIZE}^" \
    -gravity center \
    -extent "${THUMB_SIZE}x${THUMB_SIZE}" \
    -quality 85 "$thumb" 2>/dev/null; then
    printf '%s' "$thumb"
  fi
}

resolve_thumb_for_display() {
  local img="$1"
  local real cached canonical
  real=$(canonical_real "$img")
  if cached=$(find_cached_thumb "$real"); then
    promote_thumb "$real" "$cached"
    canonical="$(thumb_file_for_path "$real")"
    if [[ -f "$canonical" ]]; then
      printf '%s' "$canonical"
    else
      printf '%s' "$cached"
    fi
    return 0
  fi
  return 1
}
