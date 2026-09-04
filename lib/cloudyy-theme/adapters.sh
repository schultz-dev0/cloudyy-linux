#!/usr/bin/env bash

# Controlled curated-theme links, profile merges, and appearance preferences.

readonly CLOUDYY_ADAPTER_SKIP=2

_adapter_theme_is_active() {
  local theme="$1" stage
  stage="$(active_stage 2>/dev/null)" || return 1
  [[ "$(readlink -f -- "$theme" 2>/dev/null)" == "$(readlink -f -- "$stage/theme" 2>/dev/null)" ]]
}

_stable_theme_root() {
  printf '%s/current/theme\n' "$(theme_state_root)"
}

_install_stable_link_preflight() {
  local target="$1" desired="$2"
  shift 2
  local current legacy backup
  [[ -d "$(dirname -- "$target")" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  [[ -e "$desired" || -d "$desired" ]] || return 1
  [[ -e "$target" || -L "$target" ]] || return 0
  [[ -L "$target" ]] || {
    theme_error "theme integration path is occupied: $target"
    return 1
  }
  current="$(readlink -- "$target")" || return 1
  [[ "$current" == "$desired" ]] && return 0
  for legacy in "$@"; do
    if [[ "$current" == "$legacy" ]]; then
      backup="${target}.cloudyy-legacy-backup"
      [[ ! -e "$backup" && ! -L "$backup" ]] && return 0
      [[ -L "$backup" && "$(readlink -- "$backup")" == "$legacy" ]] || {
        theme_error "legacy theme backup path is occupied: $backup"
        return 1
      }
      return 0
    fi
  done
  theme_error "theme integration link has an unowned target: $target -> $current"
  return 1
}

_install_stable_link() {
  local target="$1" desired="$2"
  shift 2
  local current legacy backup
  _install_stable_link_preflight "$target" "$desired" "$@" || return $?

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    ln -s -- "$desired" "$target"
    return
  fi
  if [[ ! -L "$target" ]]; then
    theme_error "theme integration path is occupied: $target"
    return 1
  fi
  current="$(readlink -- "$target")" || return 1
  [[ "$current" == "$desired" ]] && return 0

  for legacy in "$@"; do
    if [[ "$current" == "$legacy" ]]; then
      backup="${target}.cloudyy-legacy-backup"
      if [[ -e "$backup" || -L "$backup" ]]; then
        [[ -L "$backup" && "$(readlink -- "$backup")" == "$legacy" ]] || {
          theme_error "legacy theme backup path is occupied: $backup"
          return 1
        }
        rm -f -- "$target" || return 1
      else
        mv -T -- "$target" "$backup" || return 1
      fi
      if ! ln -s -- "$desired" "$target"; then
        [[ -L "$backup" && ! -e "$target" ]] && mv -T -- "$backup" "$target" || true
        return 1
      fi
      return 0
    fi
  done

  theme_error "theme integration link has an unowned target: $target -> $current"
  return 1
}

_adapter_link() {
  local theme="$1" target="$2" relative="$3"
  shift 3
  _adapter_theme_is_active "$theme" || return 1
  _install_stable_link "$target" "$(_stable_theme_root)/$relative" "$@"
}

_backup_regular_file() {
  local path="$1" backup="$2"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  if [[ -e "$backup" || -L "$backup" ]]; then
    [[ -f "$backup" && ! -L "$backup" ]] && cmp -s -- "$path" "$backup"
    return
  fi
  cp -a -- "$path" "$backup"
}

_atomic_replace_from() {
  local path="$1" temporary="$2"
  chmod --reference="$path" "$temporary" && mv -Tf -- "$temporary" "$path"
}

_validate_renamed_legacy_link() {
  local old="$1" new="$2" desired="$3"
  shift 3
  local current legacy owned=false backup
  [[ -d "$(dirname -- "$new")" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  [[ -e "$desired" ]] || return 1

  if [[ -e "$old" || -L "$old" ]]; then
    [[ -L "$old" ]] || { theme_error "legacy theme path is occupied: $old"; return 1; }
    current="$(readlink -- "$old")" || return 1
    for legacy in "$@"; do
      [[ "$current" == "$legacy" ]] && { owned=true; break; }
    done
    [[ "$owned" == true ]] || {
      theme_error "legacy theme link has an unowned target: $old -> $current"
      return 1
    }
    backup="${old}.cloudyy-legacy-backup"
    if [[ -e "$backup" || -L "$backup" ]]; then
      [[ -L "$backup" && "$(readlink -- "$backup")" == "$current" ]] || return 1
    fi
  fi

  if [[ -e "$new" || -L "$new" ]]; then
    [[ -L "$new" && "$(readlink -- "$new")" == "$desired" ]] || {
      theme_error "theme integration path is occupied: $new"
      return 1
    }
  fi
}

_renamed_legacy_link() {
  local old="$1" new="$2" desired="$3"
  shift 3
  local backup created=false
  _validate_renamed_legacy_link "$old" "$new" "$desired" "$@" || return $?
  if [[ -e "$old" || -L "$old" ]]; then
    backup="${old}.cloudyy-legacy-backup"
  fi
  if [[ ! -e "$new" && ! -L "$new" ]]; then
    ln -s -- "$desired" "$new" || return 1
    created=true
  fi

  if [[ -e "$old" || -L "$old" ]]; then
    if [[ -e "$backup" || -L "$backup" ]]; then
      rm -f -- "$old" || { [[ "$created" == true ]] && rm -f -- "$new"; return 1; }
    elif ! mv -T -- "$old" "$backup"; then
      [[ "$created" == true ]] && rm -f -- "$new" || true
      return 1
    fi
  fi
}

adapter_boundary() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  _adapter_link "$theme" "$config_root/cloudyy/current-theme" '' \
    "$config_root/matugen/generated"
}

adapter_kitty() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  _adapter_link "$theme" "$config_root/kitty/current-theme.conf" applications/kitty.conf \
    "$config_root/matugen/generated/kitty-colors.conf" \
    "$HOME/.config/matugen/generated/kitty-colors.conf"
}

_gtk_import_preflight() {
  local path="$1" begin='/* >>> cloudyy-theme import >>> */'
  local end='/* <<< cloudyy-theme import <<< */' import='@import url("cloudyy-theme.css");'
  local begin_count end_count import_count block
  [[ -d "$(dirname -- "$path")" && ! -L "$(dirname -- "$path")" ]] ||
    return "$CLOUDYY_ADAPTER_SKIP"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -f "$path" && ! -L "$path" ]] || {
    theme_error "GTK theme import path is occupied: $path"
    return 1
  }
  begin_count="$(grep -Fxc "$begin" "$path" || true)"
  end_count="$(grep -Fxc "$end" "$path" || true)"
  if [[ "$begin_count" -eq 0 && "$end_count" -eq 0 ]]; then
    if grep -Fq 'cloudyy-theme.css' "$path"; then
      theme_error "unmanaged Cloudyy GTK import is ambiguous: $path"
      return 1
    fi
    return 0
  fi
  if [[ "$begin_count" -ne 1 || "$end_count" -ne 1 ]]; then
    theme_error "ambiguous Cloudyy GTK import markers: $path"
    return 1
  fi
  import_count="$(awk -v needle='cloudyy-theme.css' '
    {
      line = $0
      while ((position = index(line, needle)) > 0) {
        count++
        line = substr(line, position + length(needle))
      }
    }
    END { print count + 0 }
  ' "$path")" || return 1
  if [[ "$import_count" -ne 1 ]]; then
    theme_error "ambiguous Cloudyy GTK imports: $path"
    return 1
  fi
  block="$(awk -v begin="$begin" -v end="$end" '
    $0 == begin { inside = 1 }
    inside { print }
    inside && $0 == end { exit }
  ' "$path")" || return 1
  if [[ "$block" != "$begin"$'\n'"$import"$'\n'"$end" ]]; then
    theme_error "modified Cloudyy GTK import block: $path"
    return 1
  fi
}


# Real Matugen gtk3/gtk4 templates emit this exact line (see
# .config/matugen/templates/gtk-colors.css's [templates.gtk3]/[templates.gtk4]
# output_path) into a gtk.css Matugen never marked as Cloudyy-owned.
_gtk_legacy_import_line() {
  printf '@import url("../matugen/generated/gtk-%s.css");' "$1"
}

# Broader than the exact fingerprint above: any line shaped like a Matugen
# GTK import, so a modified/unexpected variant is detected (and left alone)
# instead of silently ignored.
_gtk_legacy_import_shaped_count() {
  grep -Ec '@import[[:space:]]*url\([^)]*matugen/generated/gtk-[^)]*\.css[^)]*\)' "$1" 2>/dev/null || true
}

_install_gtk_import() {
  local path="$1" version="$2" begin='/* >>> cloudyy-theme import >>> */'
  local end='/* <<< cloudyy-theme import <<< */' import='@import url("cloudyy-theme.css");'
  local temporary legacy_line legacy_count shaped_count legacy_backup
  _gtk_import_preflight "$path" || return $?
  if [[ -f "$path" ]] && grep -Fqx "$begin" "$path"; then
    return 0
  fi
  temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
  if [[ -e "$path" ]]; then
    legacy_line="$(_gtk_legacy_import_line "$version")"
    legacy_count="$(grep -Fxc -- "$legacy_line" "$path" || true)"
    shaped_count="$(_gtk_legacy_import_shaped_count "$path")"
    if [[ "$legacy_count" -eq 1 && "$shaped_count" -eq 1 ]]; then
      legacy_backup="${path}.cloudyy-legacy-backup"
      if ! _backup_regular_file "$path" "$legacy_backup" ||
        ! { awk -v legacy="$legacy_line" '$0 != legacy' "$path";
            printf '\n%s\n%s\n%s\n' "$begin" "$import" "$end"; } >"$temporary" ||
        ! _atomic_replace_from "$path" "$temporary"; then
        rm -f -- "$temporary" || true
        return 1
      fi
      return 0
    fi
    [[ "$shaped_count" -eq 0 ]] ||
      theme_error "legacy Matugen GTK import was not removed (unrecognized variant): $path"
    if ! { cat -- "$path"; printf '\n%s\n%s\n%s\n' "$begin" "$import" "$end"; } >"$temporary" ||
      ! _atomic_replace_from "$path" "$temporary"; then
      rm -f -- "$temporary" || true
      return 1
    fi
  elif ! printf '%s\n%s\n%s\n' "$begin" "$import" "$end" >"$temporary" ||
    ! chmod 0644 "$temporary" || ! mv -Tf -- "$temporary" "$path"; then
    rm -f -- "$temporary" || true
    return 1
  fi
}

_rollback_gtk_link() {
  local target="$1" prior_state="$2" prior_target="$3" backup_preexisted="$4"
  [[ "$prior_state" != desired ]] || return 0
  rm -f -- "$target" || return 1
  if [[ "$prior_state" == absent ]]; then
    return 0
  fi
  if [[ "$backup_preexisted" == true ]]; then
    ln -s -- "$prior_target" "$target"
  else
    mv -T -- "${target}.cloudyy-legacy-backup" "$target"
  fi
}

_adapter_gtk() {
  local theme="$1" version="$2" relative="$3"
  shift 3
  local config_root="${XDG_CONFIG_HOME:-$HOME/.config}" directory target desired gtk_css
  local prior_state=absent prior_target='' backup_preexisted=false result
  local created_directory=false
  directory="$config_root/gtk-${version}.0"
  target="$directory/cloudyy-theme.css"
  gtk_css="$directory/gtk.css"
  desired="$(_stable_theme_root)/$relative"
  _adapter_theme_is_active "$theme" || return 1
  if [[ -e "$directory" || -L "$directory" ]]; then
    [[ -d "$directory" && ! -L "$directory" ]] || {
      theme_error "GTK configuration directory is occupied or unsafe: $directory"
      return 1
    }
  else
    [[ -d "$config_root" && ! -L "$config_root" ]] || {
      theme_error "GTK configuration root is missing or unsafe: $config_root"
      return 1
    }
    mkdir -- "$directory" || return 1
    created_directory=true
  fi

  _install_stable_link_preflight "$target" "$desired" "$@"
  result=$?
  if [[ "$result" -ne 0 ]]; then
    [[ "$created_directory" == true ]] && rmdir -- "$directory" 2>/dev/null || true
    return "$result"
  fi
  _gtk_import_preflight "$gtk_css"
  result=$?
  if [[ "$result" -ne 0 ]]; then
    [[ "$created_directory" == true ]] && rmdir -- "$directory" 2>/dev/null || true
    return "$result"
  fi

  if [[ -L "$target" ]]; then
    prior_target="$(readlink -- "$target")" || return 1
    if [[ "$prior_target" == "$desired" ]]; then
      prior_state=desired
    else
      prior_state=legacy
      [[ ! -e "${target}.cloudyy-legacy-backup" && ! -L "${target}.cloudyy-legacy-backup" ]] ||
        backup_preexisted=true
    fi
  fi

  _install_stable_link "$target" "$desired" "$@"
  result=$?
  if [[ "$result" -ne 0 ]]; then
    [[ "$created_directory" == true ]] && rmdir -- "$directory" 2>/dev/null || true
    return "$result"
  fi
  if _install_gtk_import "$gtk_css" "$version"; then
    return 0
  else
    result=$?
  fi
  _rollback_gtk_link "$target" "$prior_state" "$prior_target" "$backup_preexisted" || true
  [[ "$created_directory" == true ]] && rmdir -- "$directory" 2>/dev/null || true
  return "$result"
}

adapter_gtk3() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  _adapter_gtk "$theme" 3 applications/gtk-3.css \
    "$config_root/matugen/generated/gtk-3.css" \
    "$HOME/.config/matugen/generated/gtk-3.css"
}

adapter_gtk4() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  _adapter_gtk "$theme" 4 applications/gtk-4.css \
    "$config_root/matugen/generated/gtk-4.css" \
    "$HOME/.config/matugen/generated/gtk-4.css"
}

adapter_wlogout() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  _adapter_link "$theme" "$config_root/wlogout/cloudyy-theme.css" applications/wlogout.css \
    "$config_root/matugen/generated/colors.css" "$HOME/.config/matugen/generated/colors.css"
}

_update_btop_setting() {
  local path="$1" temporary backup count
  [[ ! -e "$path" && ! -L "$path" ]] && return 0
  [[ -f "$path" && ! -L "$path" ]] || return 1
  count="$(grep -Ec '^[[:space:]]*color_theme[[:space:]]*=' "$path" || true)"
  [[ "$count" -le 1 ]] || { theme_error "ambiguous btop color_theme setting: $path"; return 1; }
  if [[ "$count" -eq 1 ]]; then
    grep -Eq '^[[:space:]]*color_theme[[:space:]]*=[[:space:]]*"cloudyy"[[:space:]]*$' "$path" && return 0
    if ! grep -Eq '^[[:space:]]*color_theme[[:space:]]*=[[:space:]]*"matugen"[[:space:]]*$' "$path"; then
      theme_error "btop color_theme has a custom value: $path"
      return 1
    fi
    backup="${path}.cloudyy-legacy-backup"
    _backup_regular_file "$path" "$backup" || return 1
  fi
  temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
  if ! awk '
    BEGIN { found = 0 }
    /^[[:space:]]*color_theme[[:space:]]*=/ {
      if (!found) print "color_theme = \"cloudyy\""
      found = 1
      next
    }
    { print }
    END { if (!found) print "color_theme = \"cloudyy\"" }
  ' "$path" >"$temporary" || ! chmod --reference="$path" "$temporary" ||
    ! mv -Tf -- "$temporary" "$path"; then
    rm -f -- "$temporary" || true
    return 1
  fi
}

adapter_btop() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}" result=0
  _adapter_link "$theme" "$config_root/btop/themes/cloudyy.theme" applications/btop.theme \
    "$config_root/matugen/generated/btop.theme" "$HOME/.config/matugen/generated/btop.theme" || result=$?
  [[ "$result" -eq 1 ]] && return 1
  _update_btop_setting "$config_root/btop/btop.conf" || return 1
  return "$result"
}

_update_starship_assignment() {
  local config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  local zdotdir="${ZDOTDIR:-$config_root/zsh}" path backup temporary count
  path="$zdotdir/.zshrc"
  backup="${path}.cloudyy-legacy-backup"
  local legacy='export STARSHIP_CONFIG="$HOME/.config/matugen/generated/starship.toml"'
  local desired='export STARSHIP_CONFIG="${XDG_STATE_HOME:-$HOME/.local/state}/cloudyy/current/theme/applications/starship.toml"'
  [[ -e "$path" || -L "$path" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  count="$(grep -Ec '^[[:space:]]*export[[:space:]]+STARSHIP_CONFIG=' "$path" || true)"
  [[ "$count" -le 1 ]] || { theme_error "ambiguous STARSHIP_CONFIG assignments: $path"; return 1; }
  [[ "$count" -eq 1 ]] || return "$CLOUDYY_ADAPTER_SKIP"
  grep -Fxq "$desired" "$path" && return 0
  if [[ "$count" -eq 1 ]] && ! grep -Fxq "$legacy" "$path"; then
    theme_error "STARSHIP_CONFIG has a non-Cloudyy value: $path"
    return 1
  fi
  _backup_regular_file "$path" "$backup" || return 1
  temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
  if ! awk -v legacy="$legacy" -v desired="$desired" '
    $0 == legacy { print desired; next }
    { print }
  ' "$path" >"$temporary" || ! _atomic_replace_from "$path" "$temporary"; then
    rm -f -- "$temporary" || true
    return 1
  fi
}

adapter_starship() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  _update_starship_assignment
}

# No Vesktop adapter: it's been removed from this system, nothing installed
# to theme. `_validate_renamed_legacy_link`/`_renamed_legacy_link` above are
# shared with other adapters (see their other call site below) and stay.

adapter_hyprland() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  _adapter_link "$theme" "$config_root/hypr/cloudyy-theme.conf" applications/hyprland.conf \
    "$config_root/matugen/generated/hyprcolors.conf" \
    "$HOME/.config/matugen/generated/hyprcolors.conf"
}

_emit_legacy_hypr_colors() {
  printf '%s\n' \
    '-- Hyprland theme tokens from matugen (generated hyprcolors.conf).' \
    '-- Source: ~/.config/matugen/generated/hyprcolors.conf' \
    '' \
    'local M = {}' \
    '' \
    'local path = os.getenv("HOME") .. "/.config/matugen/generated/hyprcolors.conf"' \
    'local f = io.open(path, "r")' \
    'if f then' \
    $'\tfor line in f:lines() do' \
    $'\t\tlocal name, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")' \
    $'\t\tif name and value and value ~= "" then' \
    $'\t\t\tM[name] = value' \
    $'\t\tend' \
    $'\tend' \
    $'\tf:close()' \
    'end' \
    '' \
    'M.primary = M.primary or "rgba(88c0d0ff)"' \
    'M.inverse_on_surface = M.inverse_on_surface or "rgba(595959aa)"' \
    '' \
    'return M'
}

_hypr_colors_migration_state() {
  local path="$1" desired="$2"
  [[ -e "$path" || -L "$path" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  [[ -f "$path" && ! -L "$path" ]] || {
    theme_error "Hyprland color module path is occupied: $path"
    return 1
  }
  cmp -s -- "$path" <(_emit_legacy_hypr_colors) && return 0
  cmp -s -- "$path" "$desired" && return "$CLOUDYY_ADAPTER_SKIP"
  if grep -Eq 'matugen/generated/hyprcolors\.conf|M\.(primary|inverse_on_surface)' "$path"; then
    theme_error "modified legacy Hyprland color module requires manual migration: $path"
    return 1
  fi
  return "$CLOUDYY_ADAPTER_SKIP"
}

_hypr_look_migration_state() {
  local path="$1" old_active old_inactive
  [[ -e "$path" || -L "$path" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  [[ -f "$path" && ! -L "$path" ]] || {
    theme_error "Hyprland look-and-feel module path is occupied: $path"
    return 1
  }
  old_active="$(grep -Fxc $'\t\t\tactive_border = colors.primary,' "$path" || true)"
  old_inactive="$(grep -Fxc $'\t\t\tinactive_border = colors.inverse_on_surface,' "$path" || true)"
  if [[ "$old_active" -eq 1 && "$old_inactive" -eq 1 ]]; then
    if grep -Fq 'active_border = colors.accent,' "$path" ||
      grep -Fq 'inactive_border = colors.border,' "$path"; then
      theme_error "ambiguous legacy Hyprland border tokens: $path"
      return 1
    fi
    return 0
  fi
  if [[ "$old_active" -ne 0 || "$old_inactive" -ne 0 ]] ||
    grep -Eq 'active_border[[:space:]]*=[[:space:]]*colors\.primary|inactive_border[[:space:]]*=[[:space:]]*colors\.inverse_on_surface' "$path"; then
    theme_error "modified legacy Hyprland border tokens require manual migration: $path"
    return 1
  fi
  return "$CLOUDYY_ADAPTER_SKIP"
}

_hypr_bindings_legacy_block_count() {
  local path="$1"
  awk '
    { lines[NR] = $0 }
    END {
      marker = "-- ── Appearance ───────────────────────────────────────────────"
      binding = "hl.bind(mainMod .. \" + L\", hl.dsp.exec_cmd(\"cloudyy-theme toggle\"), { desc = \"Toggle light/dark theme\" })"
      count = 0
      for (i = 1; i <= NR - 3; i += 1)
        if (lines[i] == marker && lines[i + 1] == "" && lines[i + 2] == binding && lines[i + 3] == "") count += 1
      print count
    }
  ' "$path"
}

_hypr_bindings_migration_state() {
  local path="$1" blocks toggles
  [[ -e "$path" || -L "$path" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  [[ -f "$path" && ! -L "$path" ]] || {
    theme_error "Hyprland bindings module path is occupied: $path"
    return 1
  }
  toggles="$(grep -Fc 'cloudyy-theme toggle' "$path" || true)"
  [[ "$toggles" -ne 0 ]] || return "$CLOUDYY_ADAPTER_SKIP"
  blocks="$(_hypr_bindings_legacy_block_count "$path")" || return 1
  if [[ "$toggles" -eq 1 && "$blocks" -eq 1 ]]; then
    return 0
  fi
  theme_error "modified legacy Hyprland toggle binding requires manual migration: $path"
  return 1
}

_hypr_backup_preflight() {
  local path="$1" backup="${path}.cloudyy-legacy-backup"
  [[ -e "$backup" || -L "$backup" ]] || return 0
  [[ -f "$backup" && ! -L "$backup" ]] && cmp -s -- "$path" "$backup" && return 0
  theme_error "legacy Hyprland backup path is occupied: $backup"
  return 1
}

_restore_regular_file() {
  local path="$1" backup="$2" temporary
  temporary="$(mktemp "${path}.cloudyy-restore.XXXXXXXX")" || return 1
  if ! cp -a -- "$backup" "$temporary" || ! chmod --reference="$backup" "$temporary" ||
    ! mv -Tf -- "$temporary" "$path"; then
    rm -f -- "$temporary" || true
    return 1
  fi
}

_write_hypr_look_migration() {
  local source="$1" target="$2"
  awk '
    $0 == "\t\t\tactive_border = colors.primary," {
      print "\t\t\tactive_border = colors.accent,"; next
    }
    $0 == "\t\t\tinactive_border = colors.inverse_on_surface," {
      print "\t\t\tinactive_border = colors.border,"; next
    }
    { print }
  ' "$source" >"$target"
}

_write_hypr_bindings_migration() {
  local source="$1" target="$2"
  awk '
    { lines[NR] = $0 }
    END {
      marker = "-- ── Appearance ───────────────────────────────────────────────"
      binding = "hl.bind(mainMod .. \" + L\", hl.dsp.exec_cmd(\"cloudyy-theme toggle\"), { desc = \"Toggle light/dark theme\" })"
      for (i = 1; i <= NR; i += 1) {
        if (lines[i] == marker && lines[i + 1] == "" && lines[i + 2] == binding && lines[i + 3] == "") {
          i += 3
          continue
        }
        print lines[i]
      }
    }
  ' "$source" >"$target"
}

adapter_hypr_modules() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}" hypr desired
  local path state temporary backup restore_failed=false
  local -a changed=() temporaries=() created_backups=() attempted=()
  local -A temporary_for=()
  _adapter_theme_is_active "$theme" || return 1
  hypr="$config_root/hypr"
  [[ -e "$hypr" || -L "$hypr" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  [[ -d "$hypr" && ! -L "$hypr" ]] || {
    theme_error "Hyprland configuration directory is occupied: $hypr"
    return 1
  }
  desired="$(theme_repo_root)/install/assets/defaults/hypr/colors.lua"
  [[ -f "$desired" && ! -L "$desired" ]] || return 1

  for path in "$hypr/colors.lua" "$hypr/lookandfeel.lua" "$hypr/bindings.lua"; do
    if [[ "$path" == */colors.lua ]]; then
      _hypr_colors_migration_state "$path" "$desired"
    elif [[ "$path" == */lookandfeel.lua ]]; then
      _hypr_look_migration_state "$path"
    else
      _hypr_bindings_migration_state "$path"
    fi
    state=$?
    case "$state" in
    0) changed+=("$path") ;;
    "$CLOUDYY_ADAPTER_SKIP") ;;
    *) return 1 ;;
    esac
  done
  ((${#changed[@]} > 0)) || return 0

  for path in "${changed[@]}"; do
    _hypr_backup_preflight "$path" || return 1
    temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
    temporaries+=("$temporary")
    temporary_for["$path"]="$temporary"
    if [[ "$path" == */colors.lua ]]; then
      cp -- "$desired" "$temporary"
    elif [[ "$path" == */lookandfeel.lua ]]; then
      _write_hypr_look_migration "$path" "$temporary"
    else
      _write_hypr_bindings_migration "$path" "$temporary"
    fi || {
      rm -f -- "${temporaries[@]}" || true
      return 1
    }
  done

  for path in "${changed[@]}"; do
    backup="${path}.cloudyy-legacy-backup"
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
      created_backups+=("$backup")
    fi
    if ! _backup_regular_file "$path" "$backup"; then
      rm -f -- "${temporaries[@]}" "${created_backups[@]}" || true
      return 1
    fi
  done

  for path in "${changed[@]}"; do
    attempted+=("$path")
    if ! _atomic_replace_from "$path" "${temporary_for[$path]}"; then
      for path in "${attempted[@]}"; do
        _restore_regular_file "$path" "${path}.cloudyy-legacy-backup" || restore_failed=true
      done
      rm -f -- "${temporaries[@]}" || true
      if [[ "$restore_failed" == false ]]; then
        rm -f -- "${created_backups[@]}" || true
      else
        theme_error 'Hyprland module rollback failed; legacy backups were preserved'
      fi
      return 1
    fi
  done
  rm -f -- "${temporaries[@]}" || true
}

_profile_directories() {
  local ini="$1" profiles_root
  [[ -f "$ini" && ! -L "$ini" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  profiles_root="$(dirname -- "$ini")"
  awk -F= -v root="$profiles_root" '
    function emit() {
      if (path != "") {
        if (relative == "1") print root "/" path
        else print path
      }
    }
    /^\[/ { emit(); path = ""; relative = "1"; next }
    $1 == "Path" { path = substr($0, index($0, "=") + 1); next }
    $1 == "IsRelative" { relative = substr($0, index($0, "=") + 1); next }
    END { emit() }
  ' "$ini"
}

readonly CLOUDYY_ZEN_MOD_OWNER='zen-live-theme-v1'
readonly CLOUDYY_ZEN_MOD_ID='cloudyy-theme'

# Owned chrome.css states: absent, a legacy symlink to the stable theme path,
# or a regular file generated by _zen_write_mod_css (generation marker).
_zen_mod_css_owned_file() {
  local path="$1" desired="$2"
  if [[ -L "$path" ]]; then
    [[ "$(readlink -- "$path")" == "$desired" ]]
    return
  fi
  [[ -f "$path" ]] || return 1
  local first_line
  IFS= read -r first_line <"$path" || return 1
  [[ "$first_line" =~ ^/\*\ cloudyy-generation:\ stage\.[A-Za-z0-9]{8}\ \*/$ ]]
}

_zen_write_mod_css() {
  local mod_css="$1" theme_css="$2" generation="$3" temporary
  [[ "$generation" =~ ^stage\.[A-Za-z0-9]{8}$ ]] || return 1
  temporary="$(mktemp "${mod_css}.cloudyy.XXXXXXXX")" || return 1
  if ! { printf '/* cloudyy-generation: %s */\n' "$generation"; cat -- "$theme_css"; } >"$temporary" ||
    ! chmod 600 -- "$temporary" ||
    ! mv -Tf -- "$temporary" "$mod_css"; then
    rm -f -- "$temporary"
    return 1
  fi
}

_zen_mod_entry() {
  jq -cn '{
    id:"cloudyy-theme",
    name:"Cloudyy Theme",
    description:"Live colors from the active Cloudyy theme",
    author:"Cloudyy",
    version:"1.0.0",
    enabled:true,
    cloudyyOwner:"zen-live-theme-v1"
  }'
}

_validate_zen_import() {
  local profile="$1" chrome user_chrome
  chrome="$profile/chrome"
  user_chrome="$chrome/userChrome.css"
  local import_line='@import "cloudyy-theme.css";' legacy_line='@import "cloudyy-zen-colors.css";'
  local desired_count legacy_count
  [[ ! -e "$chrome" && ! -L "$chrome" ]] && return 0
  [[ -d "$chrome" && ! -L "$chrome" ]] || return 1
  [[ ! -e "$user_chrome" && ! -L "$user_chrome" ]] && return 0
  [[ -f "$user_chrome" && ! -L "$user_chrome" ]] || return 1
  desired_count="$(grep -Fxc "$import_line" "$user_chrome" || true)"
  legacy_count="$(grep -Fxc "$legacy_line" "$user_chrome" || true)"
  [[ $((desired_count + legacy_count)) -le 1 ]] || {
    theme_error "ambiguous Zen theme imports: $user_chrome"
    return 1
  }
}

_zen_import_backup_path() {
  local profile="$1" user_chrome="$profile/chrome/userChrome.css"
  local import_line='@import "cloudyy-theme.css";' legacy_line='@import "cloudyy-zen-colors.css";'
  local desired_count legacy_count
  [[ -f "$user_chrome" && ! -L "$user_chrome" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  desired_count="$(grep -Fxc "$import_line" "$user_chrome" || true)"
  legacy_count="$(grep -Fxc "$legacy_line" "$user_chrome" || true)"
  if [[ "$legacy_count" -eq 1 ]]; then
    printf '%s.cloudyy-legacy-backup\n' "$user_chrome"
  elif [[ "$desired_count" -eq 1 ]]; then
    printf '%s.cloudyy-theme-backup\n' "$user_chrome"
  else
    return "$CLOUDYY_ADAPTER_SKIP"
  fi
}

_preflight_zen_import_backup() {
  local profile="$1" user_chrome="$profile/chrome/userChrome.css" backup result
  if backup="$(_zen_import_backup_path "$profile")"; then
    if [[ -e "$backup" || -L "$backup" ]]; then
      [[ -f "$backup" && ! -L "$backup" ]] && cmp -s -- "$user_chrome" "$backup" || {
        theme_error "Zen import backup path is occupied: $backup"
        return 1
      }
    fi
  else
    result=$?
    [[ "$result" -eq "$CLOUDYY_ADAPTER_SKIP" ]] || return 1
  fi
}

_zen_profile_preflight() {
  local profile="$1" desired="$2" chrome zen_themes mod manifest mod_css current_link legacy_link
  local path target owned=false
  chrome="$profile/chrome"
  zen_themes="$chrome/zen-themes"
  mod="$zen_themes/$CLOUDYY_ZEN_MOD_ID"
  manifest="$profile/zen-themes.json"
  mod_css="$mod/chrome.css"
  current_link="$chrome/cloudyy-theme.css"
  legacy_link="$chrome/cloudyy-zen-colors.css"
  [[ -d "$profile" && ! -L "$profile" && -e "$desired" ]] || return 1
  for path in "$chrome" "$zen_themes" "$mod"; do
    [[ ! -e "$path" && ! -L "$path" ]] || [[ -d "$path" && ! -L "$path" ]] || {
      theme_error "Zen Mod directory path is occupied: $path"
      return 1
    }
  done
  if [[ -e "$manifest" || -L "$manifest" ]]; then
    [[ -f "$manifest" && ! -L "$manifest" ]] && jq -e 'type == "object"' "$manifest" >/dev/null 2>&1 || {
      theme_error "invalid Zen Mod manifest preserved: $manifest"
      return 1
    }
    jq -e --arg id "$CLOUDYY_ZEN_MOD_ID" --arg owner "$CLOUDYY_ZEN_MOD_OWNER" '
      (has($id) | not) or (.[$id].cloudyyOwner == $owner)
    ' "$manifest" >/dev/null || {
      theme_error "unowned Zen Mod member preserved: $manifest"
      return 1
    }
  fi
  if [[ -e "$mod_css" || -L "$mod_css" ]]; then
    _zen_mod_css_owned_file "$mod_css" "$desired" || {
      theme_error "Zen Mod stylesheet path is occupied: $mod_css"
      return 1
    }
  fi
  _validate_zen_import "$profile" || return 1
  _preflight_zen_import_backup "$profile" || return 1
  if [[ -e "$current_link" || -L "$current_link" ]]; then
    [[ -L "$current_link" && "$(readlink -- "$current_link")" == "$desired" ]] || {
      theme_error "Zen theme link has an unowned target: $current_link"
      return 1
    }
  fi
  if [[ -e "$legacy_link" || -L "$legacy_link" ]]; then
    [[ -L "$legacy_link" ]] || return 1
    target="$(readlink -- "$legacy_link")" || return 1
    for path in "${XDG_CONFIG_HOME:-$HOME/.config}/matugen/generated/zen-userchrome.css" \
      "$HOME/.config/matugen/generated/zen-userchrome.css"; do
      [[ "$target" == "$path" ]] && { owned=true; break; }
    done
    [[ "$owned" == true ]] || {
      theme_error "legacy Zen theme link has an unowned target: $legacy_link -> $target"
      return 1
    }
    path="${legacy_link}.cloudyy-legacy-backup"
    [[ ! -e "$path" && ! -L "$path" ]] ||
      [[ -L "$path" && "$(readlink -- "$path")" == "$target" ]] || return 1
  fi
}

_zen_before_manifest_replace() { :; }

_zen_replace_manifest() {
  local manifest="$1" temporary="$2" existed="$3"
  if [[ "$existed" == true ]]; then
    _atomic_replace_from "$manifest" "$temporary"
  else
    mv -Tf -- "$temporary" "$manifest"
  fi
}

_zen_replace_import() {
  _atomic_replace_from "$1" "$2"
}

_zen_strip_owned_imports() {
  python3 -c '
import pathlib, sys
source, destination = map(pathlib.Path, sys.argv[1:])
owned = {b"@import \"cloudyy-theme.css\";", b"@import \"cloudyy-zen-colors.css\";"}
lines = source.read_bytes().splitlines(keepends=True)
destination.write_bytes(b"".join(line for line in lines if line.removesuffix(b"\n") not in owned))
' "$1" "$2"
}

_zen_retire_profile_links() {
  local current_link="$1" legacy_link="$2" backup="${2}.cloudyy-legacy-backup"
  [[ ! -e "$current_link" && ! -L "$current_link" ]] || rm -f -- "$current_link" || return 1
  if [[ -e "$legacy_link" || -L "$legacy_link" ]]; then
    if [[ -e "$backup" || -L "$backup" ]]; then
      rm -f -- "$legacy_link"
    else
      mv -T -- "$legacy_link" "$backup"
    fi
  fi
}

_rollback_zen_profile() {
  local manifest="$1" manifest_snapshot="$2" manifest_existed="$3" manifest_changed="$4"
  local user_chrome="$5" import_snapshot="$6" import_changed="$7" import_backup="$8"
  local import_backup_existed="$9" current_link="${10}" current_target="${11}"
  local legacy_link="${12}" legacy_target="${13}" legacy_backup_existed="${14}"
  local mod_css="${15}" mod_css_state="${16}" mod_link_target="${17}"
  local mod_css_snapshot="${18}" chrome="${19}" chrome_existed="${20}"
  local zen_themes="${21}" zen_themes_existed="${22}" mod="${23}" mod_existed="${24}"
  local restore
  if [[ "$manifest_changed" == true ]]; then
    if [[ "$manifest_existed" == true ]]; then
      restore="$(mktemp "${manifest}.cloudyy.rollback.XXXXXXXX")" || return 1
      cp -a -- "$manifest_snapshot" "$restore" && mv -Tf -- "$restore" "$manifest" || return 1
    else
      rm -f -- "$manifest" || return 1
    fi
  fi
  if [[ "$import_changed" == true ]]; then
    restore="$(mktemp "${user_chrome}.cloudyy.rollback.XXXXXXXX")" || return 1
    cp -a -- "$import_snapshot" "$restore" && mv -Tf -- "$restore" "$user_chrome" || return 1
  fi
  if [[ -n "$import_backup" && "$import_backup_existed" == false ]]; then
    rm -f -- "$import_backup" || return 1
  fi
  if [[ -n "$current_target" ]]; then
    rm -f -- "$current_link" || return 1
    ln -s -- "$current_target" "$current_link" || return 1
  fi
  if [[ -n "$legacy_target" ]]; then
    rm -f -- "$legacy_link" || return 1
    if [[ "$legacy_backup_existed" == false && -L "${legacy_link}.cloudyy-legacy-backup" ]]; then
      mv -T -- "${legacy_link}.cloudyy-legacy-backup" "$legacy_link" || return 1
    else
      ln -s -- "$legacy_target" "$legacy_link" || return 1
    fi
  fi
  case "$mod_css_state" in
  absent)
    rm -f -- "$mod_css" || return 1
    ;;
  link)
    rm -f -- "$mod_css" || return 1
    ln -s -- "$mod_link_target" "$mod_css" || return 1
    ;;
  file)
    [[ -n "$mod_css_snapshot" ]] || return 1
    rm -f -- "$mod_css" || return 1
    mv -T -- "$mod_css_snapshot" "$mod_css" || return 1
    ;;
  esac
  [[ "$mod_existed" == true ]] || rmdir -- "$mod" 2>/dev/null || true
  [[ "$zen_themes_existed" == true ]] || rmdir -- "$zen_themes" 2>/dev/null || true
  [[ "$chrome_existed" == true ]] || rmdir -- "$chrome" 2>/dev/null || true
}

_reconcile_zen_profile() {
  local profile="$1" desired="$2" generation="$3" chrome zen_themes mod mod_css manifest user_chrome
  local current_link legacy_link
  local manifest_snapshot manifest_temporary='' import_snapshot='' import_temporary='' import_backup=''
  local entry current_target='' legacy_target=''
  local manifest_existed=false manifest_changed=false import_changed=false import_backup_existed=false
  local legacy_backup_existed=false mod_css_state=absent mod_link_target='' mod_css_snapshot=''
  local chrome_existed=false zen_themes_existed=false mod_existed=false
  chrome="$profile/chrome"
  zen_themes="$chrome/zen-themes"
  mod="$zen_themes/$CLOUDYY_ZEN_MOD_ID"
  mod_css="$mod/chrome.css"
  manifest="$profile/zen-themes.json"
  user_chrome="$chrome/userChrome.css"
  current_link="$chrome/cloudyy-theme.css"
  legacy_link="$chrome/cloudyy-zen-colors.css"
  _zen_profile_preflight "$profile" "$desired" || return 1
  [[ -d "$chrome" ]] && chrome_existed=true
  [[ -d "$zen_themes" ]] && zen_themes_existed=true
  [[ -d "$mod" ]] && mod_existed=true
  [[ -f "$manifest" ]] && manifest_existed=true
  if [[ -L "$mod_css" ]]; then
    mod_css_state=link
    mod_link_target="$(readlink -- "$mod_css")" || return 1
  elif [[ -f "$mod_css" ]]; then
    mod_css_state=file
  fi
  if [[ -L "$current_link" ]]; then current_target="$(readlink -- "$current_link")" || return 1; fi
  if [[ -L "$legacy_link" ]]; then legacy_target="$(readlink -- "$legacy_link")" || return 1; fi
  [[ -L "${legacy_link}.cloudyy-legacy-backup" ]] && legacy_backup_existed=true
  manifest_snapshot="$(mktemp "${profile}/.zen-themes.cloudyy.snapshot.XXXXXXXX")" || return 1
  if [[ "$manifest_existed" == true ]]; then
    cp -a -- "$manifest" "$manifest_snapshot" || { rm -f -- "$manifest_snapshot"; return 1; }
  else
    printf '{}\n' >"$manifest_snapshot" || { rm -f -- "$manifest_snapshot"; return 1; }
  fi
  if [[ "$mod_css_state" == file ]]; then
    mod_css_snapshot="$(mktemp "${profile}/.zen-mod-css.cloudyy.snapshot.XXXXXXXX")" || {
      rm -f -- "$manifest_snapshot"
      return 1
    }
    cp -a -- "$mod_css" "$mod_css_snapshot" || {
      rm -f -- "$manifest_snapshot" "$mod_css_snapshot"
      return 1
    }
  fi
  if import_backup="$(_zen_import_backup_path "$profile" 2>/dev/null)"; then
    [[ -e "$import_backup" || -L "$import_backup" ]] && import_backup_existed=true
    import_snapshot="$(mktemp "${chrome}/.userChrome.cloudyy.snapshot.XXXXXXXX")" || { rm -f -- "$manifest_snapshot"; return 1; }
    cp -a -- "$user_chrome" "$import_snapshot" || { rm -f -- "$manifest_snapshot" "$import_snapshot"; return 1; }
  else
    import_backup=''
  fi
  if { [[ -d "$chrome" ]] || mkdir -- "$chrome"; } &&
    { [[ -d "$zen_themes" ]] || mkdir -- "$zen_themes"; } &&
    { [[ -d "$mod" ]] || mkdir -- "$mod"; }; then
    :
  else
    _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" false \
      "$user_chrome" "$import_snapshot" false "$import_backup" "$import_backup_existed" \
      "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
      "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
    rm -f -- "$manifest_snapshot" "$import_snapshot" || true
    return 1
  fi
  if ! _zen_write_mod_css "$mod_css" "$desired" "$generation"; then
    _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" false \
      "$user_chrome" "$import_snapshot" false "$import_backup" "$import_backup_existed" \
      "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
      "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
    rm -f -- "$manifest_snapshot" "$import_snapshot" || true
    return 1
  fi
  if ! entry="$(_zen_mod_entry)" ||
    ! manifest_temporary="$(mktemp "${profile}/.zen-themes.cloudyy.tmp.XXXXXXXX")"; then
    _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" false \
      "$user_chrome" "$import_snapshot" false "$import_backup" "$import_backup_existed" \
      "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
      "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
    rm -f -- "$manifest_snapshot" "$manifest_temporary" "$import_snapshot" || true
    return 1
  fi
  if ! jq --arg id "$CLOUDYY_ZEN_MOD_ID" --argjson entry "$entry" '.[$id] = $entry' \
      "$manifest_snapshot" >"$manifest_temporary"; then
    rm -f -- "$manifest_temporary"
    _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" false \
      "$user_chrome" "$import_snapshot" false "$import_backup" "$import_backup_existed" \
      "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
      "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
    rm -f -- "$manifest_snapshot" "$import_snapshot" || true
    return 1
  fi
  _zen_before_manifest_replace "$manifest"
  if { [[ "$manifest_existed" == true ]] && ! cmp -s -- "$manifest" "$manifest_snapshot"; } ||
    { [[ "$manifest_existed" == false ]] && [[ -e "$manifest" || -L "$manifest" ]]; }; then
    theme_error "Zen Mod manifest changed during reconciliation: $manifest"
    _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" false \
      "$user_chrome" "$import_snapshot" false "$import_backup" "$import_backup_existed" \
      "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
      "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
    rm -f -- "$manifest_snapshot" "$manifest_temporary" "$import_snapshot" || true
    return 1
  fi
  if ! _zen_replace_manifest "$manifest" "$manifest_temporary" "$manifest_existed"; then
    rm -f -- "$manifest_temporary"
    _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" false \
      "$user_chrome" "$import_snapshot" false "$import_backup" "$import_backup_existed" \
      "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
      "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
    rm -f -- "$manifest_snapshot" "$import_snapshot" || true
    return 1
  fi
  manifest_changed=true
  if [[ -n "$import_backup" ]]; then
    if ! _backup_regular_file "$user_chrome" "$import_backup" ||
      ! import_temporary="$(mktemp "${chrome}/.userChrome.cloudyy.tmp.XXXXXXXX")" ||
      ! _zen_strip_owned_imports "$user_chrome" "$import_temporary" ||
      ! _zen_replace_import "$user_chrome" "$import_temporary"; then
      rm -f -- "$import_temporary"
      _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" "$manifest_changed" \
        "$user_chrome" "$import_snapshot" false "$import_backup" "$import_backup_existed" \
        "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
        "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
      rm -f -- "$manifest_snapshot" "$import_snapshot" || true
      return 1
    fi
    import_changed=true
  fi
  if ! _zen_retire_profile_links "$current_link" "$legacy_link"; then
    _rollback_zen_profile "$manifest" "$manifest_snapshot" "$manifest_existed" "$manifest_changed" \
      "$user_chrome" "$import_snapshot" "$import_changed" "$import_backup" "$import_backup_existed" \
      "$current_link" "$current_target" "$legacy_link" "$legacy_target" "$legacy_backup_existed" \
      "$mod_css" "$mod_css_state" "$mod_link_target" "$mod_css_snapshot" "$chrome" "$chrome_existed" "$zen_themes" "$zen_themes_existed" "$mod" "$mod_existed" || true
    rm -f -- "$manifest_snapshot" "$import_snapshot" || true
    return 1
  fi
  rm -f -- "$manifest_snapshot" "$import_snapshot" "$mod_css_snapshot" || true
}

adapter_zen() {
  local theme="$1" stage="${2:-}" config_root="${XDG_CONFIG_HOME:-$HOME/.config}" profile desired generation
  local found=false failed=false
  _adapter_theme_is_active "$theme" || return 1
  [[ -n "$stage" ]] || stage="$(active_stage)" || return 1
  generation="${stage##*/}"
  desired="$(_stable_theme_root)/applications/zen.css"
  while IFS= read -r profile; do
    [[ -n "$profile" && -d "$profile" && ! -L "$profile" ]] || continue
    found=true
    _reconcile_zen_profile "$profile" "$desired" "$generation" || failed=true
  done < <(_profile_directories "$config_root/zen/profiles.ini" 2>/dev/null || true)
  [[ "$failed" == false ]] || return 1
  [[ "$found" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
}

_zen_removal_preflight() {
  local profile="$1" desired="$2" manifest chrome zen_themes mod mod_css signal path
  manifest="$profile/zen-themes.json"
  chrome="$profile/chrome"
  zen_themes="$chrome/zen-themes"
  mod="$zen_themes/$CLOUDYY_ZEN_MOD_ID"
  mod_css="$mod/chrome.css"
  signal="$chrome/cloudyy-theme-signal.json"
  [[ -d "$profile" && ! -L "$profile" ]] || return 1
  for path in "$chrome" "$zen_themes" "$mod"; do
    [[ ! -e "$path" && ! -L "$path" ]] || [[ -d "$path" && ! -L "$path" ]] || return 1
  done
  if [[ -e "$manifest" || -L "$manifest" ]]; then
    [[ -f "$manifest" && ! -L "$manifest" ]] && jq -e 'type == "object"' "$manifest" >/dev/null 2>&1 || return 1
    jq -e --arg id "$CLOUDYY_ZEN_MOD_ID" --arg owner "$CLOUDYY_ZEN_MOD_OWNER" '
      (has($id) | not) or (.[$id].cloudyyOwner == $owner)
    ' "$manifest" >/dev/null || return 1
  fi
  [[ ! -e "$mod_css" && ! -L "$mod_css" ]] ||
    _zen_mod_css_owned_file "$mod_css" "$desired" || return 1
  if [[ -e "$signal" || -L "$signal" ]]; then
    [[ -f "$signal" && ! -L "$signal" ]] && jq -e '
      type == "object" and (keys | sort) == ["generation", "mode", "schema"] and
      .schema == 1 and (.generation | type == "string" and test("^stage\\.[A-Za-z0-9]{8}$")) and
      (.mode == "dark" or .mode == "light")
    ' "$signal" >/dev/null 2>&1 || return 1
  fi
}

_remove_zen_profile() {
  local profile="$1" manifest chrome mod mod_css signal snapshot temporary
  manifest="$profile/zen-themes.json"
  chrome="$profile/chrome"
  mod="$chrome/zen-themes/$CLOUDYY_ZEN_MOD_ID"
  mod_css="$mod/chrome.css"
  signal="$chrome/cloudyy-theme-signal.json"
  if [[ -f "$manifest" ]] && jq -e --arg id "$CLOUDYY_ZEN_MOD_ID" 'has($id)' "$manifest" >/dev/null; then
    snapshot="$(mktemp "${profile}/.zen-themes.cloudyy.remove-snapshot.XXXXXXXX")" || return 1
    temporary="$(mktemp "${profile}/.zen-themes.cloudyy.remove.XXXXXXXX")" || {
      rm -f -- "$snapshot"
      return 1
    }
    if ! cp -a -- "$manifest" "$snapshot" ||
      ! jq --arg id "$CLOUDYY_ZEN_MOD_ID" --arg owner "$CLOUDYY_ZEN_MOD_OWNER" \
        'if .[$id].cloudyyOwner == $owner then del(.[$id]) else error("owner changed") end' \
        "$snapshot" >"$temporary" ||
      ! cmp -s -- "$manifest" "$snapshot" ||
      ! _atomic_replace_from "$manifest" "$temporary"; then
      rm -f -- "$snapshot" "$temporary"
      return 1
    fi
    rm -f -- "$snapshot" || true
  fi
  if [[ -e "$mod_css" || -L "$mod_css" ]]; then
    rm -f -- "$mod_css" || return 1
  fi
  [[ ! -d "$mod" ]] || rmdir -- "$mod" 2>/dev/null || true
  [[ ! -f "$signal" ]] || rm -f -- "$signal" || return 1
}

remove_zen_integration() {
  local config_root="${XDG_CONFIG_HOME:-$HOME/.config}" desired profile found=false failed=false
  local -a profiles=()
  desired="$(_stable_theme_root)/applications/zen.css"
  while IFS= read -r profile; do
    [[ -n "$profile" && -d "$profile" && ! -L "$profile" ]] || continue
    found=true
    profiles+=("$profile")
    _zen_removal_preflight "$profile" "$desired" || failed=true
  done < <(_profile_directories "$config_root/zen/profiles.ini" 2>/dev/null || true)
  [[ "$failed" == false ]] || return 1
  for profile in "${profiles[@]}"; do
    _remove_zen_profile "$profile" || return 1
  done
  [[ "$found" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
}

adapter_obsidian() {
  local theme="$1" obsidian found=false failed=false result appearance snippets target desired
  _adapter_theme_is_active "$theme" || return 1
  while IFS= read -r -d '' obsidian; do
    found=true
    appearance="$obsidian/appearance.json"
    snippets="$obsidian/snippets"
    target="$snippets/cloudyy-theme.css"
    desired="$(_stable_theme_root)/applications/obsidian.css"
    _validate_obsidian_appearance "$appearance" || { failed=true; continue; }
    if [[ -e "$snippets" || -L "$snippets" ]]; then
      [[ -d "$snippets" && ! -L "$snippets" ]] || { failed=true; continue; }
      _install_stable_link_preflight "$target" "$desired" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/matugen/generated/obsidian-theme.css" \
        "$HOME/.config/matugen/generated/obsidian-theme.css" || { failed=true; continue; }
    fi
    _update_obsidian_appearance "$appearance" || { failed=true; continue; }
    mkdir -p -- "$snippets" || { failed=true; continue; }
    _install_stable_link "$target" "$desired" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/matugen/generated/obsidian-theme.css" \
      "$HOME/.config/matugen/generated/obsidian-theme.css" || {
      result=$?
      [[ "$result" -eq "$CLOUDYY_ADAPTER_SKIP" ]] || failed=true
    }
  done < <(find -P "$HOME" -mindepth 2 -maxdepth 5 -type d -name .obsidian -print0 2>/dev/null)
  [[ "$failed" == false ]] || return 1
  [[ "$found" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
}

_validate_obsidian_appearance() {
  local path="$1" invalid_backup
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 0
  fi
  [[ -f "$path" && ! -L "$path" ]] || return 1
  if ! jq -e '
    type == "object"
    and ((.enabledCssSnippets // []) | type == "array" and all(.[]; type == "string"))
    and ([((.enabledCssSnippets // [])[]) | select(. == "matugen-theme")] | length <= 1)
    and ([((.enabledCssSnippets // [])[]) | select(. == "cloudyy-theme")] | length <= 1)
  ' "$path" >/dev/null 2>&1; then
    invalid_backup="${path}.cloudyy-invalid-backup"
    _backup_regular_file "$path" "$invalid_backup" || true
    theme_error "invalid Obsidian appearance preserved: $path"
    return 1
  fi
}

_update_obsidian_appearance() {
  local path="$1" temporary backup has_legacy
  _validate_obsidian_appearance "$path" || return $?
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
    if ! printf '{"enabledCssSnippets":["cloudyy-theme"]}\n' >"$temporary" ||
      ! mv -Tf -- "$temporary" "$path"; then
      rm -f -- "$temporary" || true
      return 1
    fi
    return 0
  fi
  if jq -e '(.enabledCssSnippets // []) | index("cloudyy-theme") != null and index("matugen-theme") == null' \
    "$path" >/dev/null; then
    return 0
  fi
  has_legacy="$(jq -r '((.enabledCssSnippets // []) | index("matugen-theme")) != null' "$path")" || return 1
  if [[ "$has_legacy" == true ]]; then
    backup="${path}.cloudyy-legacy-backup"
  else
    backup="${path}.cloudyy-theme-backup"
  fi
  _backup_regular_file "$path" "$backup" || return 1
  temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
  if ! jq '
    (.enabledCssSnippets // []) as $snippets
    | .enabledCssSnippets = (
        if ($snippets | index("cloudyy-theme")) != null then
          [$snippets[] | select(. != "matugen-theme")]
        elif ($snippets | index("matugen-theme")) != null then
          [$snippets[] | if . == "matugen-theme" then "cloudyy-theme" else . end]
        else $snippets + ["cloudyy-theme"] end
      )
  ' "$path" >"$temporary" || ! _atomic_replace_from "$path" "$temporary"; then
    rm -f -- "$temporary" || true
    return 1
  fi
}

_update_chromium_flags() {
  local flags="$1" executable="$2" process="$3" label="$4"
  local begin='# >>> cloudyy-theme chromium >>>' end='# <<< cloudyy-theme chromium <<<'
  local extension begin_count end_count begin_line end_line temporary
  extension="--load-extension=$(_stable_theme_root)/applications/chromium"
  if [[ ! -e "$flags" ]]; then
    command -v "$executable" >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"
    temporary="$(mktemp "${flags}.cloudyy.XXXXXXXX")" || return 1
    if ! printf '%s\n%s\n%s\n' "$begin" "$extension" "$end" >"$temporary" ||
      ! mv -Tf -- "$temporary" "$flags"; then
      rm -f -- "$temporary" || true
      return 1
    fi
  else
    [[ -f "$flags" && ! -L "$flags" ]] || return 1
    begin_count="$(grep -Fxc "$begin" "$flags" || true)"
    end_count="$(grep -Fxc "$end" "$flags" || true)"
    if [[ "$begin_count" -eq 0 && "$end_count" -eq 0 ]]; then
      if grep -Eq '^[[:space:]]*--load-extension([=[:space:]]|$)' "$flags"; then
        theme_error "unowned $label --load-extension flag is present: $flags"
        return 1
      fi
      temporary="$(mktemp "${flags}.cloudyy.XXXXXXXX")" || return 1
      if ! { cat -- "$flags"; [[ ! -s "$flags" || "$(tail -c 1 -- "$flags")" == $'\n' ]] || printf '\n';
        printf '%s\n%s\n%s\n' "$begin" "$extension" "$end"; } >"$temporary" ||
        ! chmod --reference="$flags" "$temporary" || ! mv -Tf -- "$temporary" "$flags"; then
        rm -f -- "$temporary" || true
        return 1
      fi
    elif [[ "$begin_count" -eq 1 && "$end_count" -eq 1 ]]; then
      begin_line="$(grep -Fn "$begin" "$flags" | cut -d: -f1)"
      end_line="$(grep -Fn "$end" "$flags" | cut -d: -f1)"
      [[ "$begin_line" -lt "$end_line" ]] || return 1
      if awk -v first="$begin_line" -v last="$end_line" 'NR < first || NR > last' "$flags" |
        grep -Eq '^[[:space:]]*--load-extension([=[:space:]]|$)'; then
        theme_error "unowned $label --load-extension flag is present: $flags"
        return 1
      fi
      temporary="$(mktemp "${flags}.cloudyy.XXXXXXXX")" || return 1
      if ! awk -v first="$begin_line" -v last="$end_line" -v b="$begin" -v x="$extension" -v e="$end" '
        NR == first { print b; print x; print e }
        NR < first || NR > last { print }
      ' "$flags" >"$temporary" || ! chmod --reference="$flags" "$temporary" ||
        ! mv -Tf -- "$temporary" "$flags"; then
        rm -f -- "$temporary" || true
        return 1
      fi
    else
      theme_error "ambiguous Cloudyy $label markers: $flags"
      return 1
    fi
  fi
  if pgrep -x "$process" >/dev/null 2>&1; then
    theme_error "$label theme is ready; pending restart or manual reload at chrome://extensions"
  fi
}

adapter_chromium() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}" result status="$CLOUDYY_ADAPTER_SKIP"
  local -a flags=("$config_root/chromium-flags.conf" "$config_root/helium-browser-flags.conf")
  local -a executables=(chromium helium-browser) processes=(chromium helium) labels=(Chromium Helium)
  local index
  _adapter_theme_is_active "$theme" || return 1
  [[ -d "$config_root" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  for index in "${!flags[@]}"; do
    if _update_chromium_flags "${flags[$index]}" "${executables[$index]}" \
      "${processes[$index]}" "${labels[$index]}"; then
      status=0
    else
      result=$?
      [[ "$result" -eq "$CLOUDYY_ADAPTER_SKIP" ]] || return "$result"
    fi
  done
  return "$status"
}

adapter_vscode() {
  local theme="$1" config_root="${XDG_CONFIG_HOME:-$HOME/.config}" candidate found=false
  _adapter_theme_is_active "$theme" || return 1
  for candidate in Code 'Code - OSS' VSCodium Cursor; do
    [[ -d "$config_root/$candidate/User" ]] && found=true
  done
  [[ "$found" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
  "$(theme_repo_root)/bin/cloudyy-code-update-vscodium" "$theme/applications/vscode.json"
}

_owned_automode_service() {
  local path="$1" expected_helper="$2"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(grep -Ec '^[[:space:]]*ExecStart=' "$path" || true)" -eq 1 ]] || return 1
  grep -Fxq 'Description=Cloudyy — auto light/dark mode switcher' "$path" &&
    grep -Fxq 'Type=oneshot' "$path" &&
    grep -Fxq "ExecStart=${expected_helper}" "$path"
}

_owned_automode_timer() {
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] || return 1
  grep -Fxq 'Description=Cloudyy — auto mode check timer' "$path" &&
    grep -Fxq 'OnCalendar=*:0/5' "$path" &&
    grep -Fxq 'WantedBy=timers.target' "$path"
}

adapter_retire_automode() {
  local theme="$1" units service timer helper have_service=false have_timer=false
  _adapter_theme_is_active "$theme" || return 1
  units="$HOME/.config/systemd/user"
  service="$units/theme-automode.service"
  timer="$units/theme-automode.timer"
  helper="$HOME/cloudyy-linux/bin/cloudyy-quickshell-automode-switch"

  if [[ -e "$service" || -L "$service" ]]; then
    _owned_automode_service "$service" "$helper" || {
      theme_error "unowned legacy automode service preserved: $service"
      return 1
    }
    have_service=true
  fi
  if [[ -e "$timer" || -L "$timer" ]]; then
    _owned_automode_timer "$timer" || {
      theme_error "unowned legacy automode timer preserved: $timer"
      return 1
    }
    have_timer=true
  fi
  [[ "$have_service" == true || "$have_timer" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
  command -v systemctl >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"

  if [[ "$have_timer" == true ]]; then
    systemctl --user disable --now theme-automode.timer >/dev/null 2>&1 || return 1
  fi
  if [[ "$have_service" == true ]]; then
    systemctl --user stop theme-automode.service >/dev/null 2>&1 || return 1
  fi
  [[ "$have_service" != true ]] || rm -f -- "$service" || return 1
  [[ "$have_timer" != true ]] || rm -f -- "$timer" || return 1
  systemctl --user daemon-reload >/dev/null 2>&1
}

_theme_mode() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  jq -er '.mode | select(. == "dark" or . == "light")' "$theme/theme.json"
}

adapter_mode_gsettings() {
  local theme="$1" mode scheme dark_value keys
  mode="$(_theme_mode "$theme")" || return 1
  command -v gsettings >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"
  gsettings list-schemas 2>/dev/null | grep -Fxq org.gnome.desktop.interface || return "$CLOUDYY_ADAPTER_SKIP"
  if [[ "$mode" == dark ]]; then
    scheme=prefer-dark
    dark_value=true
  else
    scheme=prefer-light
    dark_value=false
  fi
  keys="$(gsettings list-keys org.gnome.desktop.interface 2>/dev/null)" || return 1
  grep -Fxq color-scheme <<<"$keys" || return 1
  gsettings set org.gnome.desktop.interface color-scheme "$scheme" >/dev/null 2>&1 || return 1
  if grep -Fxq gtk-application-prefer-dark-mode <<<"$keys"; then
    gsettings set org.gnome.desktop.interface gtk-application-prefer-dark-mode \
      "$dark_value" >/dev/null 2>&1 || return 1
  fi
}

adapter_mode_portal() {
  local theme="$1"
  _theme_mode "$theme" >/dev/null || return 1
  return "$CLOUDYY_ADAPTER_SKIP"
}

_update_qt_config() {
  local path="$1" value="$2" temporary
  [[ -f "$path" && ! -L "$path" ]] || return "$CLOUDYY_ADAPTER_SKIP"
  temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
  if ! awk -v value="$value" '
    BEGIN { found = 0; in_appearance = 0; saw_appearance = 0 }
    /^\[Appearance\][[:space:]]*$/ {
      saw_appearance = 1
      in_appearance = 1
      print
      next
    }
    /^\[/ {
      if (in_appearance && !found) {
        print "color_scheme_path=" value
        found = 1
      }
      in_appearance = 0
      print
      next
    }
    in_appearance && /^[[:space:]]*color_scheme_path[[:space:]]*=/ {
      if (!found) print "color_scheme_path=" value
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        if (!saw_appearance) print "[Appearance]"
        print "color_scheme_path=" value
      }
    }
  ' "$path" >"$temporary" || ! chmod --reference="$path" "$temporary" ||
    ! mv -Tf -- "$temporary" "$path"; then
    rm -f -- "$temporary" || true
    return 1
  fi
}

adapter_mode_qt() {
  local theme="$1" mode config_root="${XDG_CONFIG_HOME:-$HOME/.config}" palette
  local applied=false failed=false result config toolkit
  mode="$(_theme_mode "$theme")" || return 1
  for toolkit in qt6ct qt5ct; do
    config="$config_root/$toolkit/$toolkit.conf"
    [[ -e "$config" ]] || continue
    [[ "$mode" == dark ]] && palette="/usr/share/$toolkit/colors/darker.conf" || \
      palette="/usr/share/$toolkit/colors/airy.conf"
    if _update_qt_config "$config" "$palette"; then
      applied=true
    else
      result=$?
      [[ "$result" -eq "$CLOUDYY_ADAPTER_SKIP" ]] || failed=true
    fi
  done
  [[ "$failed" == false ]] || return 1
  [[ "$applied" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
}

_rewrite_user_prefs() {
  local path="$1"
  shift
  local temporary keys='' key line
  [[ ! -e "$path" || ( -f "$path" && ! -L "$path" ) ]] || return 1
  for line in "$@"; do
    key="${line#*\"}"
    key="${key%%\"*}"
    [[ -n "$keys" ]] && keys+=$'\t'
    keys+="$key"
  done
  temporary="$(mktemp "${path}.cloudyy.XXXXXXXX")" || return 1
  if [[ -f "$path" ]]; then
    awk -v keys="$keys" '
      BEGIN {
        count = split(keys, values, "\t")
        for (i = 1; i <= count; i++) owned[values[i]] = 1
      }
      match($0, /^[[:space:]]*user_pref\("[^"]+"/) {
        fragment = substr($0, RSTART, RLENGTH)
        sub(/^[[:space:]]*user_pref\("/, "", fragment)
        sub(/"$/, "", fragment)
        if (fragment in owned) next
      }
      { print }
    ' "$path" >"$temporary" || { rm -f -- "$temporary"; return 1; }
  fi
  for line in "$@"; do
    printf '%s\n' "$line" >>"$temporary" || { rm -f -- "$temporary"; return 1; }
  done
  [[ ! -f "$path" ]] || chmod --reference="$path" "$temporary" || { rm -f -- "$temporary"; return 1; }
  mv -Tf -- "$temporary" "$path"
}

_apply_profile_prefs() {
  local ini="$1"
  shift
  local profile found=false failed=false
  while IFS= read -r profile; do
    [[ -d "$profile" && ! -L "$profile" ]] || continue
    found=true
    _rewrite_user_prefs "$profile/user.js" "$@" || failed=true
  done < <(_profile_directories "$ini" 2>/dev/null || true)
  [[ "$failed" == false ]] || return 1
  [[ "$found" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
}

adapter_mode_firefox() {
  local theme="$1" mode dark_value
  local applied=false failed=false result ini
  mode="$(_theme_mode "$theme")" || return 1
  [[ "$mode" == dark ]] && dark_value=1 || dark_value=0
  for ini in "$HOME/.mozilla/firefox/profiles.ini" \
    "$HOME/.var/app/org.mozilla.firefox/.mozilla/firefox/profiles.ini"; do
    [[ -e "$ini" ]] || continue
    if _apply_profile_prefs "$ini" \
      'user_pref("layout.css.prefers-color-scheme.content-override", 3);' \
      "user_pref(\"ui.systemUsesDarkTheme\", ${dark_value});" \
      "user_pref(\"browser.theme.content-theme\", ${dark_value});" \
      "user_pref(\"browser.theme.toolbar-theme\", ${dark_value});"; then
      applied=true
    else
      result=$?
      [[ "$result" -eq "$CLOUDYY_ADAPTER_SKIP" ]] || failed=true
    fi
  done
  [[ "$failed" == false ]] || return 1
  [[ "$applied" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
}

adapter_mode_zen() {
  local theme="$1" mode dark_value scheme config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  mode="$(_theme_mode "$theme")" || return 1
  [[ "$mode" == dark ]] && { dark_value=1; scheme=0; } || { dark_value=0; scheme=1; }
  _apply_profile_prefs "$config_root/zen/profiles.ini" \
    'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
    "user_pref(\"ui.systemUsesDarkTheme\", ${dark_value});" \
    "user_pref(\"zen.view.window.scheme\", ${scheme});"
}
