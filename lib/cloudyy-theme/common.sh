#!/usr/bin/env bash

# Shared paths, error codes, and active-stage inspection for cloudyy-theme.

readonly CLOUDYY_THEME_EXIT_USAGE=2
readonly CLOUDYY_THEME_EXIT_ACTIVE_STATE=3
readonly CLOUDYY_THEME_EXIT_VALIDATION=10
readonly CLOUDYY_THEME_EXIT_STAGING=11
readonly CLOUDYY_THEME_EXIT_PROMOTION=12
readonly CLOUDYY_THEME_EXIT_RECONCILE=20

# action:function dispatch table for reconcile_integrations (lib/cloudyy-theme/reload.sh).
# The bare action-name allowlist below is derived from this, not maintained separately.
# No Vesktop entry: it's been removed from this system, nothing to theme or reload.
readonly -a CLOUDYY_THEME_INTEGRATIONS=(
  'link-boundary:adapter_boundary'
  'link-kitty:adapter_kitty'
  'link-gtk3:adapter_gtk3'
  'link-gtk4:adapter_gtk4'
  'link-wlogout:adapter_wlogout'
  'link-btop:adapter_btop'
  'link-starship:adapter_starship'
  'link-hyprland:adapter_hyprland'
  'migrate-hypr-modules:adapter_hypr_modules'
  'link-zen:adapter_zen'
  'link-obsidian:adapter_obsidian'
  'chromium:adapter_chromium'
  'vscode:adapter_vscode'
  'retire-automode:adapter_retire_automode'
  'mode-gsettings:adapter_mode_gsettings'
  'mode-portal:adapter_mode_portal'
  'mode-qt:adapter_mode_qt'
  'mode-firefox:adapter_mode_firefox'
  'mode-zen:adapter_mode_zen'
  'reload-hyprland:reload_hyprland'
  'reload-quickshell:reload_quickshell'
  'reload-kitty:reload_kitty'
  'reload-nvim:reload_nvim'
  'reload-btop:reload_btop'
  'reload-gtk:reload_gtk'
  'reload-wlogout:reload_wlogout'
  'reload-starship:reload_starship'
  'reload-zen:reload_zen'
  'reload-obsidian:reload_obsidian'
  'reload-chromium:reload_chromium'
)

_cloudyy_theme_reconcile_actions() {
  local entry
  printf '%s\n' wallpaper compatibility-state
  for entry in "${CLOUDYY_THEME_INTEGRATIONS[@]}"; do
    printf '%s\n' "${entry%%:*}"
  done
}
declare -a CLOUDYY_THEME_RECONCILE_ACTIONS
mapfile -t CLOUDYY_THEME_RECONCILE_ACTIONS < <(_cloudyy_theme_reconcile_actions)
readonly -a CLOUDYY_THEME_RECONCILE_ACTIONS

theme_repo_root() {
  cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd
}

theme_state_root() {
  local state_parent
  state_parent="$(realpath -m -- "${XDG_STATE_HOME:-$HOME/.local/state}")" || return 1
  printf '%s/cloudyy\n' "$state_parent"
}

theme_stages_root() {
  printf '%s/theme-stages\n' "$(theme_state_root)"
}

theme_state_layout_safe() {
  local state_root stages_root
  state_root="$(theme_state_root)" || return 1
  stages_root="$(theme_stages_root)" || return 1
  [[ ! -L "$state_root" && ( ! -e "$state_root" || -d "$state_root" ) ]] || return 1
  [[ ! -L "$stages_root" && ( ! -e "$stages_root" || -d "$stages_root" ) ]]
}

theme_runtime_lock_available() {
  [[ -n "${XDG_RUNTIME_DIR:-}" && -d "$XDG_RUNTIME_DIR" && -w "$XDG_RUNTIME_DIR" ]]
}

theme_error() {
  printf 'cloudyy-theme: %s\n' "$*" >&2
}

theme_lock_path() {
  if theme_runtime_lock_available; then
    printf '%s/cloudyy-theme.lock\n' "$XDG_RUNTIME_DIR"
    return
  fi

  printf '%s/theme.lock\n' "$(theme_state_root)"
}

_theme_pointer_stage() {
  local pointer="$1"
  local stages_root resolved
  stages_root="$(theme_stages_root)"

  [[ -d "$stages_root" && ! -L "$stages_root" ]] || return 1
  stages_root="$(readlink -f -- "$stages_root")" || return 1
  [[ -L "$pointer" ]] || return 1
  resolved="$(readlink -f -- "$pointer" 2>/dev/null)" || return 1
  [[ -d "$resolved" && ! -L "$resolved" ]] || return 1
  [[ "$(dirname -- "$resolved")" == "$stages_root" ]] || return 1
  [[ "${resolved##*/}" == stage.* ]] || return 1
  printf '%s\n' "$resolved"
}

active_stage() {
  local state_root stage
  theme_state_layout_safe || return 1
  state_root="$(theme_state_root)"
  stage="$(_theme_pointer_stage "$state_root/current")" || return 1
  _stage_is_valid "$stage" || return 1
  printf '%s\n' "$stage"
}
