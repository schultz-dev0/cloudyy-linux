#!/usr/bin/env bash
# Installs Cloudyy's privileged Zen live-theme bridge without replacing user files.
set -euo pipefail -E

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
readonly ASSET_DIR="${SCRIPT_DIR}/../assets/zen"
readonly ZEN_ROOT="${CLOUDYY_ZEN_INSTALL_ROOT:-/opt/zen-browser-bin}"
readonly OWNER_MARKER='CLOUDYY-ZEN-LIVE-THEME: zen-live-theme-v1'
readonly PREF_TARGET="$ZEN_ROOT/defaults/pref/cloudyy-autoconfig.js"
readonly CFG_TARGET="$ZEN_ROOT/cloudyy.cfg"
readonly PREF_ASSET="${ASSET_DIR}/cloudyy-autoconfig.js"
readonly CFG_ASSET="${ASSET_DIR}/cloudyy.cfg"

if [[ -t 1 ]]; then
  RED=$'\e[1;31m' GREEN=$'\e[1;32m' YELLOW=$'\e[1;33m' BLUE=$'\e[1;34m' RESET=$'\e[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' RESET=''
fi
_ts() { date '+%H:%M:%S'; }
log()      { printf '%s[*]%s  [%s] %s\n' "$BLUE"   "$RESET" "$(_ts)" "$1"; }
log_ok()   { printf '%s[✓]%s  [%s] %s\n' "$GREEN"  "$RESET" "$(_ts)" "$1"; }
log_warn() { printf '%s[!]%s  [%s] %s\n' "$YELLOW" "$RESET" "$(_ts)" "$1"; }
log_error(){ printf '%s[✗]%s  [%s] %s\n' "$RED"    "$RESET" "$(_ts)" "$1" >&2; }

_err_handler() {
  log_error "Unexpected error on line ${BASH_LINENO[0]}: ${BASH_COMMAND}"
}
trap '_err_handler' ERR

_is_real_file() {
  [[ -f "$1" && ! -L "$1" ]]
}

_has_owner_marker() {
  _is_real_file "$1" && grep -Fq -- "$OWNER_MARKER" "$1"
}

_require_zen() {
  if [[ ! -d "$ZEN_ROOT" || -L "$ZEN_ROOT" || ! -d "$ZEN_ROOT/defaults/pref" || -L "$ZEN_ROOT/defaults/pref" ]]; then
    log_warn "Zen installation unavailable at ${ZEN_ROOT}."
    return 2
  fi
}

_require_assets() {
  if ! _is_real_file "$PREF_ASSET" || ! _is_real_file "$CFG_ASSET"; then
    log_error "Zen live-theme bridge assets are unavailable."
    return 1
  fi
}

_check_config_conflicts() {
  local pref
  for pref in "$ZEN_ROOT"/defaults/pref/*.js; do
    _is_real_file "$pref" || continue
    grep -Fq -- 'general.config.filename' "$pref" || continue
    if [[ "$pref" == "$PREF_TARGET" ]] && _has_owner_marker "$pref"; then
      continue
    fi
    log_error "Conflicting Zen autoconfig preference: ${pref}"
    return 1
  done
}

_target_is_installable() {
  local target="$1"
  local asset="$2"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi
  if ! _is_real_file "$target"; then
    log_error "Refusing to replace occupied Zen path: ${target}"
    return 1
  fi
  if cmp -s -- "$target" "$asset" || _has_owner_marker "$target"; then
    return 0
  fi
  log_error "Refusing to replace unowned Zen file: ${target}"
  return 1
}

_install_bridge() {
  _require_zen || return $?
  _require_assets || return $?
  _check_config_conflicts || return $?
  _target_is_installable "$PREF_TARGET" "$PREF_ASSET" || return $?
  _target_is_installable "$CFG_TARGET" "$CFG_ASSET" || return $?

  local stage
  if ! stage="$(mktemp -d)"; then
    log_error "Could not create a private staging directory."
    return 1
  fi
  if ! install -m 0644 -- "$PREF_ASSET" "$stage/cloudyy-autoconfig.js" \
    || ! install -m 0644 -- "$CFG_ASSET" "$stage/cloudyy.cfg"; then
    rm -rf -- "$stage"
    log_error "Could not stage Zen live-theme bridge assets."
    return 1
  fi

  local -a write_cmd=(install)
  local -a remove_cmd=(rm)
  if [[ ! -w "$ZEN_ROOT" || ! -w "$ZEN_ROOT/defaults/pref" ]]; then
    write_cmd=(sudo install)
    remove_cmd=(sudo rm)
  fi

  local pref_existed=0
  if _is_real_file "$PREF_TARGET"; then
    pref_existed=1
    if ! cp -- "$PREF_TARGET" "$stage/previous-pref"; then
      rm -rf -- "$stage"
      log_error "Could not preserve the existing Cloudyy Zen preference."
      return 1
    fi
  fi

  if ! "${write_cmd[@]}" -m 0644 -- "$stage/cloudyy-autoconfig.js" "$PREF_TARGET"; then
    rm -rf -- "$stage"
    log_error "Could not install the Cloudyy Zen preference."
    return 1
  fi

  if ! "${write_cmd[@]}" -m 0644 -- "$stage/cloudyy.cfg" "$CFG_TARGET"; then
    local rollback_failed=0
    if (( pref_existed )); then
      "${write_cmd[@]}" -m 0644 -- "$stage/previous-pref" "$PREF_TARGET" || rollback_failed=1
    else
      "${remove_cmd[@]}" -f -- "$PREF_TARGET" || rollback_failed=1
    fi
    rm -rf -- "$stage"
    if (( rollback_failed )); then
      log_error "Zen bridge installation failed and preference rollback also failed."
    else
      log_error "Zen bridge installation failed; the preference was rolled back."
    fi
    return 1
  fi

  rm -rf -- "$stage"
  log_ok "Zen live-theme bridge installed."
  log_warn "Restart Zen once to enable live theme reloads."
}

_verify_bridge() {
  _require_zen || return $?
  _require_assets || return $?
  _check_config_conflicts || return $?

  if ! _is_real_file "$PREF_TARGET" || ! cmp -s -- "$PREF_TARGET" "$PREF_ASSET" \
    || ! _is_real_file "$CFG_TARGET" || ! cmp -s -- "$CFG_TARGET" "$CFG_ASSET"; then
    log_error "Zen live-theme bridge verification failed."
    return 1
  fi
  log_ok "Zen live-theme bridge verified."
}

_remove_bridge() {
  _require_zen || return $?

  local target
  for target in "$PREF_TARGET" "$CFG_TARGET"; do
    if [[ -e "$target" || -L "$target" ]]; then
      if ! _has_owner_marker "$target"; then
        log_error "Refusing to remove conflicting Zen path: ${target}"
        return 1
      fi
    fi
  done

  local -a remove_cmd=(rm)
  if [[ ! -w "$ZEN_ROOT" || ! -w "$ZEN_ROOT/defaults/pref" ]]; then
    remove_cmd=(sudo rm)
  fi
  for target in "$PREF_TARGET" "$CFG_TARGET"; do
    if _has_owner_marker "$target"; then
      if ! "${remove_cmd[@]}" -f -- "$target"; then
        log_error "Could not remove owned Zen path: ${target}"
        return 1
      fi
    fi
  done
  log_ok "Zen live-theme bridge removed."
}

_remove_profile_integration() {
  local library status=0
  for library in common.sh package.sh adapters.sh; do
    if [[ ! -f "$REPO_ROOT/lib/cloudyy-theme/$library" ]]; then
      log_error "Cloudyy theme library is unavailable: ${library}"
      return 1
    fi
    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib/cloudyy-theme/$library"
  done
  remove_zen_integration || status=$?
  if [[ "$status" -ne 0 && "$status" -ne "$CLOUDYY_ADAPTER_SKIP" ]]; then
    log_error "Zen profile cleanup found a conflict; bridge assets were preserved."
    return 1
  fi
}

_remove_integration() {
  _remove_profile_integration || return $?
  _remove_bridge
}

main() {
  case "${1:-}" in
    install) _install_bridge ;;
    verify) _verify_bridge ;;
    remove) _remove_integration ;;
    *)
      log_error "Usage: $0 install|verify|remove"
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  status=0
  main "$@" || status=$?
  exit "$status"
fi
