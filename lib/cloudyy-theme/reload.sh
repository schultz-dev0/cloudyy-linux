#!/usr/bin/env bash

# Consumer reload actions and whole-operation integration orchestration.

_process_running() {
  local process
  for process in "$@"; do
    pgrep -x "$process" >/dev/null 2>&1 && return 0
  done
  return 1
}

reload_hyprland() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  _process_running Hyprland || return "$CLOUDYY_ADAPTER_SKIP"
  command -v hyprctl >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"
  hyprctl reload >/dev/null 2>&1
}

reload_quickshell() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  _process_running quickshell qs || return "$CLOUDYY_ADAPTER_SKIP"
  command -v quickshell >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"
  quickshell -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell" ipc call theme reload >/dev/null 2>&1
}

reload_kitty() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  _process_running kitty || return "$CLOUDYY_ADAPTER_SKIP"
  command -v kitty >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"
  if [[ -S /tmp/kitty ]] && kitty @ --to unix:/tmp/kitty set-colors --all --configured \
    "$theme/applications/kitty.conf" >/dev/null 2>&1; then
    return 0
  fi
  command -v pkill >/dev/null 2>&1 || return 1
  pkill -SIGUSR1 -x kitty >/dev/null 2>&1
}

reload_nvim() {
  local theme="$1" socket found=false failed=false
  _adapter_theme_is_active "$theme" || return 1
  command -v nvim >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"
  for socket in "${XDG_RUNTIME_DIR:-/run/user/${UID}}"/nvim.*.0; do
    [[ -S "$socket" ]] || continue
    found=true
    nvim --server "$socket" --remote-expr "execute('ThemeReload')" >/dev/null 2>&1 || failed=true
  done
  [[ "$failed" == false ]] || return 1
  [[ "$found" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
}

reload_btop() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  _process_running btop || return "$CLOUDYY_ADAPTER_SKIP"
  command -v pkill >/dev/null 2>&1 || return 1
  pkill -USR2 -x btop >/dev/null 2>&1
}

_reload_passive_consumer() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  return "$CLOUDYY_ADAPTER_SKIP"
}

# GTK apps read gtk.css at startup; no live-reload target is part of this
# system (Thunar used to be poked here via quit+relaunch, but it isn't
# installed on Cloudyy — that dance only ever ran for a user who happened
# to have it, and cost seconds of blocking under the exclusive theme lock
# when it did), so this is passive like the other CSS consumers below.
reload_gtk() { _reload_passive_consumer "$1"; }
reload_wlogout() { _reload_passive_consumer "$1"; }
reload_starship() { _reload_passive_consumer "$1"; }
# No reload_vesktop: it's been removed from this system.
reload_obsidian() { _reload_passive_consumer "$1"; }

_zen_reload_prerequisites_succeeded() {
  [[ -n "${CLOUDYY_ACTIVATION_DRAFT:-}" ]] || return 1
  jq -e '
    .reconcile.actions["link-zen"].status == "success" and
    .reconcile.actions["mode-zen"].status == "success"
  ' "$CLOUDYY_ACTIVATION_DRAFT" >/dev/null 2>&1
}

_zen_bridge_installed() {
  local install_root="${CLOUDYY_ZEN_INSTALL_ROOT:-/opt/zen-browser-bin}" repo_root
  local installed_pref installed_config asset_pref asset_config
  repo_root="$(theme_repo_root)" || {
    theme_error 'Zen live-theme bridge state could not be verified'
    return 1
  }
  installed_pref="$install_root/defaults/pref/cloudyy-autoconfig.js"
  installed_config="$install_root/cloudyy.cfg"
  asset_pref="$repo_root/install/assets/zen/cloudyy-autoconfig.js"
  asset_config="$repo_root/install/assets/zen/cloudyy.cfg"
  if [[ -f "$installed_pref" && ! -L "$installed_pref" &&
    -f "$installed_config" && ! -L "$installed_config" ]] &&
    cmp -s -- "$installed_pref" "$asset_pref" &&
    cmp -s -- "$installed_config" "$asset_config"; then
    return 0
  fi
  theme_error 'Zen live-theme bridge unavailable; colors apply after bridge install and one Zen restart'
  return "$CLOUDYY_ADAPTER_SKIP"
}

_write_zen_theme_signal() {
  local profile="$1" generation="$2" mode="$3" chrome signal temporary LC_ALL=C
  chrome="$profile/chrome"
  signal="$chrome/cloudyy-theme-signal.json"
  [[ -d "$chrome" && ! -L "$chrome" ]] || return 1
  [[ "$generation" =~ ^stage\.[A-Za-z0-9]{8}$ ]] || return 1
  [[ "$mode" == dark || "$mode" == light ]] || return 1
  if [[ -e "$signal" || -L "$signal" ]]; then
    [[ -f "$signal" && ! -L "$signal" ]] && jq -e '
      type == "object" and (keys | sort) == ["generation", "mode", "schema"] and
      .schema == 1 and (.generation | type == "string" and test("^stage\\.[A-Za-z0-9]{8}$")) and
      (.mode == "dark" or .mode == "light")
    ' "$signal" >/dev/null 2>&1 || return 1
  fi
  temporary="$(mktemp "$chrome/.cloudyy-theme-signal.XXXXXXXX")" || return 1
  if ! jq -cn --arg generation "$generation" --arg mode "$mode" \
    '{schema:1,generation:$generation,mode:$mode}' >"$temporary" ||
    ! chmod 600 -- "$temporary" ||
    ! python3 -c 'import os, sys; fd=os.open(sys.argv[1], os.O_RDONLY); os.fsync(fd); os.close(fd)' "$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  if ! mv -Tf -- "$temporary" "$signal"; then
    rm -f -- "$temporary"
    return 1
  fi
  python3 -c 'import os, sys; fd=os.open(sys.argv[1], os.O_RDONLY | os.O_DIRECTORY); os.fsync(fd); os.close(fd)' "$chrome"
}

reload_zen() {
  local theme="$1" stage="$2" mode generation profile
  local found=false failed=false
  _adapter_theme_is_active "$theme" || return 1
  _zen_reload_prerequisites_succeeded || return "$CLOUDYY_ADAPTER_SKIP"
  [[ "$stage" == "$(active_stage)" ]] || return 1
  generation="${stage##*/}"
  mode="$(_theme_mode "$theme")" || return 1
  while IFS= read -r profile; do
    [[ -n "$profile" && -d "$profile" && ! -L "$profile" ]] || continue
    found=true
    _write_zen_theme_signal "$profile" "$generation" "$mode" || failed=true
  done < <(_profile_directories "${XDG_CONFIG_HOME:-$HOME/.config}/zen/profiles.ini" 2>/dev/null || true)
  [[ "$failed" == false ]] || return 1
  [[ "$found" == true ]] || return "$CLOUDYY_ADAPTER_SKIP"
  # The signal doubles as the startup-convergence record, so it is written even
  # when Zen is closed. Without the bridge, neither live updates nor restart
  # color convergence can happen — warn regardless of process state.
  _zen_bridge_installed || true
}

reload_chromium() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  if _process_running chromium; then
    theme_error 'Chromium theme is pending restart or manual reload at chrome://extensions'
  fi
  if _process_running helium; then
    theme_error 'Helium theme is pending restart or manual reload at chrome://extensions'
  fi
  return "$CLOUDYY_ADAPTER_SKIP"
}

_run_recorded_integration() {
  local stage="$1" theme="$2" action="$3" function="$4" result status record_status=0 lock_fd
  if "$function" "$theme" "$stage"; then
    result=0
  else
    result=$?
  fi
  case "$result" in
  0) status=success ;;
  "$CLOUDYY_ADAPTER_SKIP") status=skip ;;
  *) status=failure ;;
  esac
  # Recording runs under a lock: this function is called from several
  # backgrounded jobs at once (see reconcile_integrations), all sharing the
  # one activation-draft file. The adapter/reload call above is the slow,
  # subprocess-heavy part and stays fully concurrent — only the brief
  # read-modify-write of the draft is serialized.
  if [[ -n "${CLOUDYY_ACTIVATION_DRAFT:-}" ]] && exec {lock_fd}>"${CLOUDYY_ACTIVATION_DRAFT}.lock"; then
    flock -x "$lock_fd"
    _record_activation_result "$stage" "$action" "$status" || record_status=1
    exec {lock_fd}>&-
  else
    _record_activation_result "$stage" "$action" "$status" || record_status=1
  fi
  [[ "$status" != failure && "$record_status" -eq 0 ]]
}

# Runs one batch of "action:function" entries concurrently and waits for all
# of them; returns failure if any entry failed (adapter failure or a lost
# activation-result write). Used by reconcile_integrations to keep the two
# phases below internally parallel without a helper array-by-reference.
_run_integration_batch() {
  local stage="$1" theme="$2"
  shift 2
  local -a pids=()
  local entry action function pid batch_failed=false

  for entry in "$@"; do
    action="${entry%%:*}"
    function="${entry#*:}"
    _run_recorded_integration "$stage" "$theme" "$action" "$function" &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do
    wait "$pid" || batch_failed=true
  done
  [[ "$batch_failed" == false ]]
}

reconcile_integrations() {
  local stage="$1" theme="$stage/theme" failed=false entry action
  local -a non_reload=() reload=()

  # Two phases, not one flat parallel fan-out: reload-* actions (hyprctl
  # reload, kitty's remote-control push, etc.) assume every link-*/mode-*
  # action already finished writing its target file — running them in the
  # same wave risked reloading against half-written config. Actions within
  # a phase don't share files with each other, so those stay concurrent.
  for entry in "${CLOUDYY_THEME_INTEGRATIONS[@]}"; do
    action="${entry%%:*}"
    if [[ "$action" == reload-* ]]; then
      reload+=("$entry")
    else
      non_reload+=("$entry")
    fi
  done

  _run_integration_batch "$stage" "$theme" "${non_reload[@]}" || failed=true
  _run_integration_batch "$stage" "$theme" "${reload[@]}" || failed=true
  [[ -z "${CLOUDYY_ACTIVATION_DRAFT:-}" ]] || rm -f -- "${CLOUDYY_ACTIVATION_DRAFT}.lock"
  [[ "$failed" == false ]]
}
