#!/usr/bin/env bash
# Run nonessential installation finishing work.
set -euo pipefail -E

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_DIR="$(cd "${INSTALL_DIR}/.." && pwd)"

usage() {
  printf 'Usage: %s [--unattended] [--help]\n\nBootstrap optional editor state and launch the first-run configurator.\n' "$(basename "$0")"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

bash "${SCRIPT_DIR}/nvim.sh"

if [[ "${1:-}" != "--unattended" && "${CLOUDYY_UNATTENDED:-0}" != "1" ]]; then
  config_ctl="${REPO_DIR}/bin/cloudyy-config"
  [[ -x "$config_ctl" ]] && "$config_ctl" --first-run
fi
