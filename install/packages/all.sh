#!/usr/bin/env bash
# Install Cloudyy's required and standard package sets.
set -euo pipefail -E

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  printf 'Usage: %s [--help]\n\nInstall Cloudyy package sets and detected GPU drivers.\n' "$(basename "$0")"
}

case "${1:-}" in
--help | -h) usage; exit 0 ;;
esac

exec bash "${SCRIPT_DIR}/install.sh" "$@"
