#!/usr/bin/env bash
# Shared wallpaper thumbnail cache helpers (Quickshell wallpaper picker).
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
  local real hash thumb lock lock_fd tmp cached canonical
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
  lock="${thumb}.lock"
  tmp="${thumb}.$$.png"

  # Concurrent callers can request the same source (e.g. a theme's preview
  # falls back to wallpapers[0] — see package.sh — so both get thumbnailed
  # in the same batch); lock per-thumbnail and re-check after acquiring
  # rather than let two writers race the same destination path.
  exec {lock_fd}>"$lock" || return 1
  if ! flock -w 30 "$lock_fd"; then
    exec {lock_fd}>&-
    return 1
  fi
  if [[ -f "$thumb" ]]; then
    exec {lock_fd}>&-
    printf '%s' "$thumb"
    return 0
  fi

  # Inlined rather than a helper function: callers export gen_thumb into
  # fresh `bash -c` subshells for parallel generation (see wallpapers.sh),
  # and only what's explicitly export -f'd exists there — a second function
  # gen_thumb called out to would need its own export at every call site.
  if command -v vipsthumbnail &>/dev/null; then
    # Single-threaded per call on purpose: callers fan out one gen_thumb
    # per image concurrently, so N of these run in parallel without each
    # one also fighting for every core on its own.
    VIPS_CONCURRENCY=1 vipsthumbnail "$real" \
      --size "${THUMB_SIZE}x${THUMB_SIZE}" \
      --smartcrop=centre \
      --path "${tmp}[strip]" 2>/dev/null
  else
    local converter="convert"
    command -v magick &>/dev/null && converter="magick"
    "$converter" "${real}[0]" -strip \
      -resize "${THUMB_SIZE}x${THUMB_SIZE}^" \
      -gravity center \
      -extent "${THUMB_SIZE}x${THUMB_SIZE}" \
      -quality 85 "$tmp" 2>/dev/null
  fi

  if [[ -f "$tmp" ]]; then
    mv -f -- "$tmp" "$thumb"
    printf '%s' "$thumb"
  else
    rm -f -- "$tmp"
  fi
  exec {lock_fd}>&-
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
