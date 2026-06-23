#!/usr/bin/env bash
# App catalog for App Library — delegates to apps-catalog.py (cached).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "${SCRIPT_DIR}/apps-catalog.py" "${1:-list}" "${@:2}"
