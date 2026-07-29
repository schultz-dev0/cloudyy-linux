#!/usr/bin/env bash
# Deploy tracked configuration, seed defaults, and initialise theme state.
set -euo pipefail -E

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_DIR="$(cd "${INSTALL_DIR}/.." && pwd)"

usage() {
  printf 'Usage: %s [--unattended] [--help]\n\nDeploy Cloudyy configuration and initialise desktop settings.\n' "$(basename "$0")"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

flags=()
[[ "${1:-}" == "--unattended" || "${CLOUDYY_UNATTENDED:-0}" == "1" ]] && flags+=(--unattended)

CLOUDYY_INSTALL_ORCHESTRATED=1 bash "${SCRIPT_DIR}/deploy.sh" "${flags[@]}"
bash "${SCRIPT_DIR}/schema.sh"
bash "${SCRIPT_DIR}/region-time.sh"

state_conf="${HOME}/.config/hypr/theme_state/state.conf"
default_wall="${HOME}/Wallpapers/Dark/cloudyy.jpg"
current_wall="${HOME}/.config/hypr/theme_state/current_wallpaper/current.jpg"
theme_ctl="${REPO_DIR}/bin/cloudyy-theme"

if [[ -x "$theme_ctl" ]]; then
  if [[ ! -f "$state_conf" ]] || ! grep -q 'CURRENT_WALL="[^"]' "$state_conf" 2>/dev/null; then
    if [[ -f "$default_wall" ]]; then
      mkdir -p "$(dirname "$state_conf")"
      printf 'THEME_MODE="dark"\nCURRENT_WALL="%s"\n' "$default_wall" >"$state_conf"
    fi
  fi
  if [[ ! -f "$current_wall" && -f "$default_wall" ]]; then
    mkdir -p "$(dirname "$current_wall")"
    cp "$default_wall" "$current_wall"
  fi
  "$theme_ctl" restore >/dev/null 2>&1 ||
    printf '[!] Theme bootstrap failed (non-fatal — run cloudyy-theme restore later).\n' >&2
fi
