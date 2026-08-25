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

reload_gtk() {
  local theme="$1" attempt daemon_pid
  _adapter_theme_is_active "$theme" || return 1
  command -v thunar >/dev/null 2>&1 || return "$CLOUDYY_ADAPTER_SKIP"
  _process_running Thunar thunar || return "$CLOUDYY_ADAPTER_SKIP"
  thunar -q >/dev/null 2>&1 || return 1
  for ((attempt = 0; attempt < 20; attempt += 1)); do
    _process_running Thunar thunar || break
    sleep 0.1
  done
  _process_running Thunar thunar && return 1
  (
    [[ -z "${theme_lock_fd:-}" ]] || exec {theme_lock_fd}>&-
    exec thunar --daemon
  ) >/dev/null 2>&1 &
  daemon_pid=$!
  for ((attempt = 0; attempt < 20; attempt += 1)); do
    _process_running Thunar thunar && return 0
    kill -0 "$daemon_pid" >/dev/null 2>&1 || {
      wait "$daemon_pid" 2>/dev/null || true
      return 1
    }
    sleep 0.1
  done
  return 1
}

_reload_passive_consumer() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  return "$CLOUDYY_ADAPTER_SKIP"
}

reload_wlogout() { _reload_passive_consumer "$1"; }
reload_starship() { _reload_passive_consumer "$1"; }
# No reload_vesktop: it's been removed from this system.
reload_zen() { _reload_passive_consumer "$1"; }
reload_obsidian() { _reload_passive_consumer "$1"; }

reload_chromium() {
  local theme="$1"
  _adapter_theme_is_active "$theme" || return 1
  if _process_running chromium; then
    theme_error 'Chromium will apply the curated theme after its next restart'
  fi
  return "$CLOUDYY_ADAPTER_SKIP"
}

_run_recorded_integration() {
  local stage="$1" theme="$2" action="$3" function="$4" result status
  if "$function" "$theme"; then
    result=0
  else
    result=$?
  fi
  case "$result" in
  0) status=success ;;
  "$CLOUDYY_ADAPTER_SKIP") status=skip ;;
  *) status=failure ;;
  esac
  _record_activation_result "$stage" "$action" "$status" || true
  [[ "$status" != failure ]]
}

reconcile_integrations() {
  local stage="$1" theme="$stage/theme" failed=false entry action function

  for entry in "${CLOUDYY_THEME_INTEGRATIONS[@]}"; do
    action="${entry%%:*}"
    function="${entry#*:}"
    _run_recorded_integration "$stage" "$theme" "$action" "$function" || failed=true
  done
  [[ "$failed" == false ]]
}
