#!/usr/bin/env bash

# Wallpaper daemon and legacy state compatibility for cloudyy-theme.

readonly CLOUDYY_WALLPAPER_BACKEND_UNAVAILABLE=21

wallpaper_state_root() {
  printf '%s/hypr/theme_state\n' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

wallpaper_pool_root() {
  printf '%s\n' "${CLOUDYY_WALLPAPER_DIR:-$HOME/Wallpapers}"
}

theme_wallpaper_one() {
  local stage wallpaper
  stage="$(active_stage)" || return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  wallpaper="$(find -P "$stage/theme/wallpapers" -mindepth 1 -maxdepth 1 -type f -name '1.*' -print -quit)"
  [[ -n "$wallpaper" && -f "$wallpaper" && ! -L "$wallpaper" ]] || return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  printf '%s\n' "$wallpaper"
}

saved_wallpaper() {
  local state_root state_file snapshot key value
  state_root="$(wallpaper_state_root)"
  state_file="$state_root/state.conf"
  snapshot="$state_root/current_wallpaper/current.jpg"

  if [[ -f "$state_file" && ! -L "$state_file" ]]; then
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
      [[ "$key" == 'CURRENT_WALL' ]] || continue
      value="${value%\"}"
      value="${value#\"}"
      if [[ -n "$value" && -f "$value" ]]; then
        printf '%s\n' "$value"
        return 0
      fi
      break
    done <"$state_file"
  fi

  if [[ -f "$snapshot" && ! -L "$snapshot" ]]; then
    printf '%s\n' "$snapshot"
    return 0
  fi
  return 1
}

write_compatibility_state() {
  local wallpaper="$1" stage mode state_root snapshot_root
  local temporary_state temporary_public temporary_snapshot
  [[ -f "$wallpaper" && "$wallpaper" != *$'\n'* && "$wallpaper" != *$'\r'* && "$wallpaper" != *'"'* ]] || return 1
  stage="$(active_stage)" || return 1
  mode="$(jq -r '.mode' "$stage/theme/theme.json")" || return 1
  state_root="$(wallpaper_state_root)"
  snapshot_root="$state_root/current_wallpaper"

  [[ ! -L "$state_root" && ( ! -e "$state_root" || -d "$state_root" ) ]] || return 1
  [[ ! -L "$snapshot_root" && ( ! -e "$snapshot_root" || -d "$snapshot_root" ) ]] || return 1
  mkdir -p -- "$state_root" "$snapshot_root" || return 1
  [[ ! -L "$state_root/state.conf" && ! -L "$state_root/state" && ! -L "$snapshot_root/current.jpg" ]] || return 1

  temporary_state="$(mktemp "$state_root/.state.conf.XXXXXXXX")" || return 1
  temporary_public="$(mktemp "$state_root/.state.XXXXXXXX")" || {
    rm -f -- "$temporary_state"
    return 1
  }
  temporary_snapshot="$(mktemp "$snapshot_root/.current.jpg.XXXXXXXX")" || {
    rm -f -- "$temporary_state" "$temporary_public"
    return 1
  }

  if ! printf 'THEME_MODE="%s"\nCURRENT_WALL="%s"\n' "$mode" "$wallpaper" >"$temporary_state" ||
    ! printf '%s\n' "$([[ "$mode" == light ]] && printf '1' || printf '0')" >"$temporary_public" ||
    ! cp -- "$wallpaper" "$temporary_snapshot" ||
    ! chmod 600 -- "$temporary_state" "$temporary_public" "$temporary_snapshot" ||
    ! mv -Tf -- "$temporary_snapshot" "$snapshot_root/current.jpg" ||
    ! mv -Tf -- "$temporary_public" "$state_root/state" ||
    ! mv -Tf -- "$temporary_state" "$state_root/state.conf"; then
    rm -f -- "$temporary_state" "$temporary_public" "$temporary_snapshot" || true
    return 1
  fi
}

seed_theme_wallpaper() {
  local wallpaper
  wallpaper="$(theme_wallpaper_one)" || return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  write_compatibility_state "$wallpaper"
}

_select_wallpaper_backend() {
  CLOUDYY_WALLPAPER_CLIENT=()
  CLOUDYY_WALLPAPER_DAEMON=()
  if command -v awww >/dev/null 2>&1 && command -v awww-daemon >/dev/null 2>&1; then
    CLOUDYY_WALLPAPER_CLIENT=(awww)
    CLOUDYY_WALLPAPER_DAEMON=(awww-daemon)
  elif command -v swww >/dev/null 2>&1 && command -v swww-daemon >/dev/null 2>&1; then
    CLOUDYY_WALLPAPER_CLIENT=(swww)
    CLOUDYY_WALLPAPER_DAEMON=(swww-daemon)
  else
    return "$CLOUDYY_WALLPAPER_BACKEND_UNAVAILABLE"
  fi
}

_ensure_wallpaper_daemon() {
  local attempt
  pgrep -x "${CLOUDYY_WALLPAPER_DAEMON[0]}" >/dev/null 2>&1 && return 0
  (
    [[ -z "${theme_lock_fd:-}" ]] || exec {theme_lock_fd}>&-
    exec "${CLOUDYY_WALLPAPER_DAEMON[@]}"
  ) >/dev/null 2>&1 &
  for ((attempt = 0; attempt < 50; attempt += 1)); do
    pgrep -x "${CLOUDYY_WALLPAPER_DAEMON[0]}" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

_wallpaper_transition() {
  local transitions=(simple grow center outer wipe wave any)
  printf '%s\n' "${transitions[RANDOM % ${#transitions[@]}]}"
}

apply_wallpaper() {
  local wallpaper="$1" transition="${2:-$(_wallpaper_transition)}"
  [[ -f "$wallpaper" ]] || return 1
  _select_wallpaper_backend || return $?
  _ensure_wallpaper_daemon || return 1
  "${CLOUDYY_WALLPAPER_CLIENT[@]}" img "$wallpaper" \
    --transition-type "$transition" --transition-duration 1 --transition-fps 60
}

_apply_and_save_wallpaper() {
  local wallpaper="$1" result
  if apply_wallpaper "$wallpaper"; then
    write_compatibility_state "$wallpaper"
    return
  else
    result=$?
  fi
  return "$result"
}

_wallpaper_pool() {
  local stage mode pool_root mode_root search_root
  local -a depth=(-maxdepth 1)
  stage="$(active_stage)" || return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  mode="$(jq -r '.mode' "$stage/theme/theme.json")" || return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  pool_root="$(wallpaper_pool_root)"
  [[ -d "$pool_root" && -r "$pool_root" ]] || {
    theme_error "wallpaper directory is unavailable: $pool_root"
    return 1
  }
  mode_root="$pool_root/${mode^}"
  search_root="$pool_root"
  if [[ -d "$mode_root" && -r "$mode_root" ]]; then
    search_root="$mode_root"
    depth=()
  fi
  CLOUDYY_WALLPAPERS=()
  mapfile -d '' CLOUDYY_WALLPAPERS < <(find -L "$search_root" "${depth[@]}" -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -print0 2>/dev/null | sort -z)
  ((${#CLOUDYY_WALLPAPERS[@]} > 0)) || {
    theme_error "no wallpapers found in $search_root"
    return 1
  }
}

wallpaper_random() {
  _wallpaper_pool || return $?
  _apply_and_save_wallpaper "${CLOUDYY_WALLPAPERS[RANDOM % ${#CLOUDYY_WALLPAPERS[@]}]}"
}

wallpaper_next() {
  local current='' current_real wallpaper_real index next=0
  _wallpaper_pool || return $?
  current="$(saved_wallpaper 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    current_real="$(realpath -m -- "$current")"
    for index in "${!CLOUDYY_WALLPAPERS[@]}"; do
      wallpaper_real="$(realpath -m -- "${CLOUDYY_WALLPAPERS[$index]}")"
      if [[ "$wallpaper_real" == "$current_real" ]]; then
        next=$((index + 1))
        break
      fi
    done
  fi
  ((next < ${#CLOUDYY_WALLPAPERS[@]})) || next=0
  _apply_and_save_wallpaper "${CLOUDYY_WALLPAPERS[$next]}"
}

wallpaper_set_image() {
  local wallpaper="$1"
  [[ -f "$wallpaper" ]] || {
    theme_error "image not found: $wallpaper"
    return 1
  }
  wallpaper="$(realpath -- "$wallpaper")" || return 1
  _apply_and_save_wallpaper "$wallpaper"
}

wallpaper_restore() {
  local wallpaper
  wallpaper="$(saved_wallpaper 2>/dev/null || true)"
  [[ -n "$wallpaper" ]] || wallpaper="$(theme_wallpaper_one)" || return "$CLOUDYY_THEME_EXIT_ACTIVE_STATE"
  _apply_and_save_wallpaper "$wallpaper"
}

wallpaper_tag() {
  local wallpaper="$1" mode="$2" pool link
  [[ "$mode" == dark || "$mode" == light ]] || return "$CLOUDYY_THEME_EXIT_USAGE"
  [[ -f "$wallpaper" ]] || return 1
  wallpaper="$(realpath -- "$wallpaper")" || return 1
  pool="$(wallpaper_pool_root)/${mode^}"
  link="$pool/${wallpaper##*/}"
  mkdir -p -- "$pool" || return 1
  [[ ! -e "$link" || -L "$link" ]] || {
    theme_error "wallpaper tag path is occupied: $link"
    return 1
  }
  ln -sfn -- "$wallpaper" "$link"
}

wallpaper_untag() {
  local wallpaper="$1" mode="$2" link
  [[ "$mode" == dark || "$mode" == light ]] || return "$CLOUDYY_THEME_EXIT_USAGE"
  link="$(wallpaper_pool_root)/${mode^}/${wallpaper##*/}"
  [[ -L "$link" ]] || {
    theme_error "wallpaper tag does not exist: $link"
    return 1
  }
  rm -f -- "$link"
}
