#!/usr/bin/env bash

# Built-in package validation and private staging for cloudyy-theme.

# Vesktop is not a curated consumer: it's been removed from this system, so
# there's nothing installed to theme. See adapters.sh/reload.sh for the same
# note at the adapter/reload boundary.
readonly -a CLOUDYY_THEME_APPLICATION_FILES=(
  'applications/btop.theme'
  'applications/chromium/manifest.json'
  'applications/gtk-3.css'
  'applications/gtk-4.css'
  'applications/hyprland.conf'
  'applications/kitty.conf'
  'applications/nvim.lua'
  'applications/obsidian.css'
  'applications/starship.toml'
  'applications/vscode.json'
  'applications/wlogout.css'
  'applications/zen.css'
)

readonly -a CLOUDYY_THEME_COLOR_ROLES=(
  accent accentAlt accentMuted background border error info onAccent selection shadow
  success surface surfaceOverlay surfaceRaised text textMuted warning
)

_package_error() {
  theme_error "$*"
  return 1
}

_is_theme_slug() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

theme_package_root() {
  local slug="$1"
  local package
  _is_theme_slug "$slug" || return 1
  package="$(theme_repo_root)/themes/$slug"
  [[ -d "$package" && ! -L "$package" ]] || return 1
  printf '%s\n' "$package"
}

_validate_theme_metadata() {
  local package="$1" expected_slug="$2"
  local roles_json
  roles_json="$(printf '%s\n' "${CLOUDYY_THEME_COLOR_ROLES[@]}" | jq -R . | jq -s 'sort')"

  jq -e --arg slug "$expected_slug" --argjson roles "$roles_json" '
    type == "object"
    and (keys | sort == ["colors", "mode", "name", "slug"])
    and (.slug == $slug)
    and (.name | type == "string" and test("[^[:space:]]"))
    and (.mode == "dark" or .mode == "light")
    and (.colors | type == "object")
    and (.colors | keys | sort == $roles)
    and (.colors | all(.[]; type == "string" and test("^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$")))
  ' "$package/theme.json" >/dev/null 2>&1 || _package_error "invalid theme metadata: $package/theme.json"
}

_validate_package_tree() {
  local package="$1" path relative
  local -A allowed_directories=(
    [applications]=1
    [applications/chromium]=1
    [wallpapers]=1
  )
  local -A required_files=([theme.json]=1)
  # Optional top-level files a package may ship but need not. preview.png is
  # consumed by _theme_preview_path() for the picker; the validator has to
  # allow it or `use <slug>` rejects any theme that ships one.
  local -A optional_files=([preview.png]=1)
  local application

  for application in "${CLOUDYY_THEME_APPLICATION_FILES[@]}"; do
    required_files["$application"]=1
  done

  while IFS= read -r -d '' path; do
    relative="${path#"$package/"}"
    [[ -L "$path" ]] && { _package_error "symbolic links are not allowed: $relative"; return 1; }
    if [[ -d "$path" ]]; then
      [[ -n "${allowed_directories[$relative]:-}" ]] || { _package_error "unexpected package directory: $relative"; return 1; }
      continue
    fi
    if [[ -f "$path" ]]; then
      if [[ -n "${required_files[$relative]:-}" || -n "${optional_files[$relative]:-}" || "$relative" == wallpapers/* ]]; then
        continue
      fi
      _package_error "unexpected package file: $relative"
      return 1
    fi
    _package_error "non-regular package entry: $relative"
    return 1
  done < <(find -P "$package" -mindepth 1 -print0)

  for application in "${CLOUDYY_THEME_APPLICATION_FILES[@]}"; do
    path="$package/$application"
    [[ -f "$path" && ! -L "$path" && -s "$path" ]] || {
      _package_error "required non-empty application asset is missing: $application"
      return 1
    }
  done

  [[ -f "$package/theme.json" && ! -L "$package/theme.json" && -s "$package/theme.json" ]] || {
    _package_error 'required non-empty theme.json is missing'
    return 1
  }
}

_validate_native_assets() {
  local package="$1" slug name mode
  slug="$(jq -r '.slug' "$package/theme.json")"
  name="$(jq -r '.name' "$package/theme.json")"
  mode="$(jq -r '.mode' "$package/theme.json")"
  python3 "$(theme_repo_root)/lib/cloudyy-theme/validate_assets.py" "$package" "$slug" "$name" "$mode" || return 1
}

_validate_wallpapers() {
  local package="$1" wallpaper filename stem extension
  local wallpaper_one_count=0
  local found_wallpaper=false
  local -A wallpaper_stems=()

  while IFS= read -r -d '' wallpaper; do
    found_wallpaper=true
    filename="${wallpaper##*/}"
    stem="${filename%.*}"
    extension="${filename##*.}"
    extension="${extension,,}"
    [[ -f "$wallpaper" && ! -L "$wallpaper" ]] || {
      _package_error "wallpaper is not a regular file: $filename"
      return 1
    }
    [[ "$stem" =~ ^[1-9][0-9]*$ ]] || {
      _package_error "wallpaper stem is not a positive unambiguous integer: $filename"
      return 1
    }
    case "$extension" in
    jpg | jpeg | png | webp) ;;
    *)
      _package_error "unsupported wallpaper extension: $filename"
      return 1
      ;;
    esac
    [[ -z "${wallpaper_stems[$stem]:-}" ]] || {
      _package_error "duplicate wallpaper stem: $stem"
      return 1
    }
    wallpaper_stems["$stem"]=1
    [[ "$stem" == '1' ]] && ((wallpaper_one_count += 1))
    identify "$wallpaper" >/dev/null 2>&1 || {
      _package_error "wallpaper cannot be decoded: $filename"
      return 1
    }
  done < <(find -P "$package/wallpapers" -mindepth 1 -maxdepth 1 -print0)

  [[ "$found_wallpaper" == true && "$wallpaper_one_count" -eq 1 ]] || {
    _package_error 'exactly one decodable wallpaper with stem 1 is required'
    return 1
  }
}

validate_theme_package() {
  local package="$1" expected_slug="${2:-${1##*/}}"
  [[ -d "$package" && ! -L "$package" ]] || {
    _package_error "theme package is not a regular directory: $package"
    return 1
  }
  _is_theme_slug "$expected_slug" || {
    _package_error "invalid theme slug: $expected_slug"
    return 1
  }

  _validate_package_tree "$package" || return 1
  _validate_theme_metadata "$package" "$expected_slug" || return 1
  _validate_native_assets "$package" || return 1
  _validate_wallpapers "$package" || return 1
}

list_themes() {
  local themes_root theme slug
  themes_root="$(theme_repo_root)/themes"
  [[ -d "$themes_root" && ! -L "$themes_root" ]] || return 0

  while IFS= read -r -d '' theme; do
    slug="${theme##*/}"
    if _is_theme_slug "$slug"; then
      printf '%s\n' "$slug"
    fi
  done < <(find -P "$themes_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  return 0
}

# A theme's wallpaper files in numeric stem order (1, 2, 3, ...) — not
# lexical, which would sort "10" before "2". UI consumers (the theme picker)
# use this for the "browse this theme's wallpapers" strip.
_theme_wallpaper_paths() {
  local package="$1" wallpaper base stem
  find -P "$package/wallpapers" -mindepth 1 -maxdepth 1 -type f -print0 2>/dev/null |
    while IFS= read -r -d '' wallpaper; do
      base="${wallpaper##*/}"
      stem="${base%.*}"
      printf '%s\t%s\n' "$stem" "$wallpaper"
    done | sort -t $'\t' -k1,1n | cut -f2-
}

# A theme's own preview.png if it ships one, else its wallpaper 1. UI
# consumers (the theme picker) use this as the thumbnail source.
_theme_preview_path() {
  local package="$1" preview
  preview="$package/preview.png"
  if [[ -f "$preview" && ! -L "$preview" ]]; then
    printf '%s\n' "$preview"
    return 0
  fi
  _theme_wallpaper_paths "$package" | sed -n '1p'
}

_cloudyy_theme_thumb_cache_ready=false
_theme_ensure_thumb_cache() {
  [[ "$_cloudyy_theme_thumb_cache_ready" == true ]] && return 0
  # Same cache dir/size as the wallpaper picker (commandcenter/scripts/
  # wallpapers.sh) — a wallpaper already thumbnailed there is an instant
  # hit here too, and nothing new needs pruning: it's the picker's cache.
  CACHE_DIR="${HOME}/.cache/rofi_thumbs"
  THUMB_SIZE=256
  mkdir -p -- "$CACHE_DIR" || return 1
  # shellcheck source=../thumb_cache.sh
  source "$(theme_repo_root)/lib/thumb_cache.sh" || return 1
  _cloudyy_theme_thumb_cache_ready=true
}

# Small display-only copy of a wallpaper/preview file, for the picker's
# carousels — decoding a 256x256 cached thumbnail is fast regardless of how
# large the source photo is. Falls back to the original path if the cache
# can't be reached (imagemagick missing, cache dir not writable, etc.); a
# consumer just decodes the full file at that point, same as before this
# existed.
_theme_display_thumbnail() {
  local path="$1" thumb
  _theme_ensure_thumb_cache || {
    printf '%s\n' "$path"
    return 0
  }
  thumb="$(gen_thumb "$path" 2>/dev/null)" && [[ -n "$thumb" ]] || {
    printf '%s\n' "$path"
    return 0
  }
  printf '%s\n' "$thumb"
}

# Thumbnails a theme needs (its preview, then each wallpaper in order) are
# generated concurrently — one background job per image, index-numbered
# temp files so results can be reassembled in order afterward.
# gen_thumb (thumb_cache.sh) locks per-thumbnail-file, so this stays safe
# even when preview and wallpapers[0] are the same underlying image.
_theme_display_thumbnails() {
  local tmp_dir="$1" i
  shift
  local -a paths=("$@") pids=()
  for i in "${!paths[@]}"; do
    _theme_display_thumbnail "${paths[$i]}" >"$tmp_dir/$i" &
    pids+=("$!")
  done
  for i in "${pids[@]}"; do
    wait "$i"
  done
  for i in "${!paths[@]}"; do
    cat -- "$tmp_dir/$i"
  done
}

list_themes_json() {
  local current="${1:-}" themes_root theme slug preview preview_thumb lines=''
  local wallpapers_json wallpaper_thumbs_json tmp_dir
  local -a wallpapers thumbs all_thumbs
  themes_root="$(theme_repo_root)/themes"
  if [[ -d "$themes_root" && ! -L "$themes_root" ]]; then
    while IFS= read -r -d '' theme; do
      slug="${theme##*/}"
      _is_theme_slug "$slug" || continue
      [[ -f "$theme/theme.json" && ! -L "$theme/theme.json" ]] || continue
      preview="$(_theme_preview_path "$theme")"
      [[ -n "$preview" ]] || continue
      mapfile -t wallpapers < <(_theme_wallpaper_paths "$theme")

      # Thumbnails are a display-only convenience for the picker (see
      # _theme_display_thumbnail) — wallpapers itself stays the real paths,
      # since set-image/apply need the actual file, not a shrunk copy.
      tmp_dir="$(mktemp -d)" || return 1
      mapfile -t all_thumbs < <(_theme_display_thumbnails "$tmp_dir" "$preview" "${wallpapers[@]}")
      rm -rf -- "$tmp_dir"
      preview_thumb="${all_thumbs[0]}"
      thumbs=("${all_thumbs[@]:1}")

      wallpapers_json="$(printf '%s\n' "${wallpapers[@]}" | jq -R . | jq -s .)"
      wallpaper_thumbs_json="$(printf '%s\n' "${thumbs[@]}" | jq -R . | jq -s .)"
      lines+="$(jq -c --arg preview "$preview_thumb" --argjson wallpapers "$wallpapers_json" \
        --argjson wallpaperThumbnails "$wallpaper_thumbs_json" \
        '{slug, name, mode, colors, preview: $preview, wallpapers: $wallpapers, wallpaperThumbnails: $wallpaperThumbnails}' "$theme/theme.json" 2>/dev/null)"$'\n'
    done < <(find -P "$themes_root" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
  fi
  printf '%s' "$lines" | jq -s --arg current "$current" '{current: $current, themes: .}'
}

_stage_is_referenced() {
  local stage="$1" pointer candidate
  local state_root
  state_root="$(theme_state_root)"
  for pointer in current previous; do
    candidate="$(_theme_pointer_stage "$state_root/$pointer" 2>/dev/null || true)"
    [[ "$candidate" == "$stage" ]] && return 0
  done
  return 1
}

_stage_is_valid() {
  local stage="$1" slug entry base
  [[ -d "$stage" && ! -L "$stage" ]] || return 1
  for entry in theme theme.name wallpaper.index activation.json; do
    [[ -e "$stage/$entry" || -L "$stage/$entry" ]] || return 1
  done
  while IFS= read -r -d '' entry; do
    base="${entry##*/}"
    case "$base" in
    theme | theme.name | wallpaper.index | activation.json) ;;
    *) return 1 ;;
    esac
  done < <(find -P "$stage" -mindepth 1 -maxdepth 1 -print0)
  [[ "$(stat -c '%a' "$stage")" == '700' ]] || return 1
  while IFS= read -r -d '' directory; do
    [[ "$(stat -c '%a' "$directory")" == '700' ]] || return 1
  done < <(find -P "$stage" -type d -print0)
  while IFS= read -r -d '' file; do
    [[ "$(stat -c '%a' "$file")" == '600' ]] || return 1
  done < <(find -P "$stage" -type f -print0)
  slug="$(jq -r '.slug' "$stage/theme/theme.json" 2>/dev/null)" || return 1
  validate_theme_package "$stage/theme" "$slug" >/dev/null 2>&1 || return 1
  [[ -f "$stage/theme.name" && ! -L "$stage/theme.name" ]] || return 1
  [[ -f "$stage/wallpaper.index" && ! -L "$stage/wallpaper.index" ]] || return 1
  [[ -f "$stage/activation.json" && ! -L "$stage/activation.json" ]] || return 1
  cmp -s <(printf '%s\n' "$slug") "$stage/theme.name" || return 1
  cmp -s <(printf '1\n') "$stage/wallpaper.index" || return 1
  _activation_document_is_valid "$stage/activation.json"
}

_activation_document_is_valid() {
  local activation="$1" actions_json previous_actions_json legacy_actions_json
  actions_json="$(printf '%s\n' "${CLOUDYY_THEME_RECONCILE_ACTIONS[@]}" | jq -R . | jq -s 'sort')" || return 1
  previous_actions_json="$(printf '%s\n' "${CLOUDYY_THEME_RECONCILE_ACTIONS[@]}" |
    jq -R 'select(. != "migrate-hypr-modules")' | jq -s 'sort')" || return 1
  legacy_actions_json="$(printf '%s\n' "${CLOUDYY_THEME_RECONCILE_ACTIONS[@]}" |
    jq -R 'select(. != "migrate-hypr-modules" and . != "retire-automode")' | jq -s 'sort')" || return 1
  jq -e --argjson expected_actions "$actions_json" \
    --argjson previous_actions "$previous_actions_json" --argjson legacy_actions "$legacy_actions_json" '
    type == "object"
    and (.prepare == {"status": "success"})
    and (
      (keys == ["prepare"])
      or (
        (keys == ["prepare", "reconcile"])
        and (
          .reconcile
          | type == "object"
          and keys == ["actions", "status"]
          and (.status == "success" or .status == "failure")
          and (.actions | type == "object" and (keys == $expected_actions or keys == $previous_actions or keys == $legacy_actions))
          and (.actions | all(.[]; type == "object" and keys == ["status"] and (.status == "success" or .status == "skip" or .status == "failure")))
          and (([.actions[].status] | any(. == "failure")) == (.status == "failure"))
        )
      )
    )
  ' "$activation" >/dev/null 2>&1
}

_remove_stage_directory() {
  local stage="$1"
  local stages_root resolved
  stages_root="$(theme_stages_root)"
  [[ -d "$stages_root" && ! -L "$stages_root" && -d "$stage" && ! -L "$stage" ]] || return 1
  stages_root="$(readlink -f -- "$stages_root")" || return 1
  resolved="$(readlink -f -- "$stage")" || return 1
  [[ "$(dirname -- "$resolved")" == "$stages_root" ]] || return 1
  rm -rf -- "$stage"
}

_cleanup_stages() {
  local stages_root stage base cleanup_failed=false
  stages_root="$(theme_stages_root)"
  [[ -d "$stages_root" ]] || return 0

  while IFS= read -r -d '' stage; do
    base="${stage##*/}"
    [[ -d "$stage" && ! -L "$stage" ]] || continue
    _stage_is_referenced "$stage" && continue
    if [[ "$base" == .tmp.* ]]; then
      _remove_stage_directory "$stage" || cleanup_failed=true
    elif [[ "$base" == stage.* ]] && _stage_is_valid "$stage"; then
      _remove_stage_directory "$stage" || cleanup_failed=true
    fi
  done < <(find -P "$stages_root" -mindepth 1 -maxdepth 1 -type d -print0)
  [[ "$cleanup_failed" == false ]]
}

promote_stage() {
  local stage="$1"
  local state_root stages_root resolved_stage old_current old_previous temporary_current temporary_previous
  state_root="$(theme_state_root)"
  stages_root="$(theme_stages_root)"
  if [[ ! -d "$stages_root" || -L "$stages_root" ]] || ! resolved_stage="$(readlink -f -- "$stage" 2>/dev/null)" || \
    [[ "${stage##*/}" != stage.* || "$(dirname -- "$resolved_stage")" != "$(readlink -f -- "$stages_root")" ]]; then
    theme_error "refusing to promote a stage outside private storage: $stage"
    return "$CLOUDYY_THEME_EXIT_PROMOTION"
  fi
  _stage_is_valid "$stage" || {
    theme_error "refusing to promote an invalid stage: $stage"
    return "$CLOUDYY_THEME_EXIT_PROMOTION"
  }

  old_current="$(_theme_pointer_stage "$state_root/current" 2>/dev/null || true)"
  if [[ -n "$old_current" ]] && ! _stage_is_valid "$old_current"; then
    old_current=''
  fi
  old_previous="$(_theme_pointer_stage "$state_root/previous" 2>/dev/null || true)"
  if [[ -n "$old_previous" ]] && ! _stage_is_valid "$old_previous"; then
    old_previous=''
  fi

  temporary_current="$state_root/.current.$RANDOM.$RANDOM"
  ln -s "theme-stages/${stage##*/}" "$temporary_current" || return "$CLOUDYY_THEME_EXIT_PROMOTION"

  if [[ -n "$old_current" ]]; then
    temporary_previous="$state_root/.previous.$RANDOM.$RANDOM"
    if ! ln -s "theme-stages/${old_current##*/}" "$temporary_previous" || ! mv -Tf -- "$temporary_previous" "$state_root/previous"; then
      rm -f -- "$temporary_current" "$temporary_previous" || true
      return "$CLOUDYY_THEME_EXIT_PROMOTION"
    fi
  elif [[ -z "$old_previous" ]]; then
    rm -f -- "$state_root/previous" || return "$CLOUDYY_THEME_EXIT_PROMOTION"
  fi

  if ! mv -Tf -- "$temporary_current" "$state_root/current"; then
    rm -f -- "$temporary_current" || true
    return "$CLOUDYY_THEME_EXIT_PROMOTION"
  fi
  if ! _cleanup_stages; then
    theme_error 'could not clean unreferenced theme stages'
    return "$CLOUDYY_THEME_EXIT_PROMOTION"
  fi
  return 0
}

prepare_theme() {
  local slug="$1" source_package state_root stages_root temporary_stage temporary_base stage
  source_package="$(theme_package_root "$slug")" || {
    theme_error "unknown shipped theme: $slug"
    return "$CLOUDYY_THEME_EXIT_VALIDATION"
  }
  validate_theme_package "$source_package" "$slug" || return "$CLOUDYY_THEME_EXIT_VALIDATION"

  state_root="$(theme_state_root)"
  stages_root="$(theme_stages_root)"
  if [[ -L "$state_root" || ( -e "$state_root" && ! -d "$state_root" ) ]] || \
    ! mkdir -p -- "$state_root" || [[ -L "$stages_root" || ( -e "$stages_root" && ! -d "$stages_root" ) ]] || \
    ! mkdir -p -- "$stages_root" || ! chmod 700 -- "$state_root" "$stages_root"; then
    theme_error 'could not create private theme stage storage'
    return "$CLOUDYY_THEME_EXIT_STAGING"
  fi
  _cleanup_stages || {
    theme_error 'could not clean interrupted theme stages'
    return "$CLOUDYY_THEME_EXIT_STAGING"
  }
  temporary_stage="$(mktemp -d "$stages_root/.tmp.XXXXXXXX")" || {
    theme_error 'could not create theme stage'
    return "$CLOUDYY_THEME_EXIT_STAGING"
  }
  if ! chmod 700 -- "$temporary_stage"; then
    _remove_stage_directory "$temporary_stage" || true
    theme_error 'could not secure theme stage'
    return "$CLOUDYY_THEME_EXIT_STAGING"
  fi

  if ! cp -a --no-dereference -- "$source_package/." "$temporary_stage/theme" || \
    ! find "$temporary_stage" -type d -exec chmod 700 {} + || \
    ! find "$temporary_stage" -type f -exec chmod 600 {} +; then
    _remove_stage_directory "$temporary_stage" || true
    theme_error 'could not copy private theme stage'
    return "$CLOUDYY_THEME_EXIT_STAGING"
  fi

  if ! {
    printf '%s\n' "$slug" >"$temporary_stage/theme.name"
    printf '1\n' >"$temporary_stage/wallpaper.index"
    printf '{"prepare":{"status":"success"}}\n' >"$temporary_stage/activation.json"
    chmod 600 -- "$temporary_stage/theme.name" "$temporary_stage/wallpaper.index" "$temporary_stage/activation.json"
  }; then
    _remove_stage_directory "$temporary_stage" || true
    theme_error 'could not write theme stage state'
    return "$CLOUDYY_THEME_EXIT_STAGING"
  fi

  if ! validate_theme_package "$temporary_stage/theme" "$slug"; then
    _remove_stage_directory "$temporary_stage" || true
    return "$CLOUDYY_THEME_EXIT_STAGING"
  fi

  temporary_base="${temporary_stage##*/}"
  stage="$stages_root/stage.${temporary_base#.tmp.}"
  if ! mv -T -- "$temporary_stage" "$stage"; then
    _remove_stage_directory "$temporary_stage" || true
    theme_error 'could not finalize theme stage'
    return "$CLOUDYY_THEME_EXIT_STAGING"
  fi
  promote_stage "$stage"
}

current_theme_slug() {
  local stage
  stage="$(active_stage)" || return 1
  cat -- "$stage/theme.name"
}
