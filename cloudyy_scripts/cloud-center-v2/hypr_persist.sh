#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

python3 -m lib.hypr_persist_lua "$@"
rc=$?
if [[ $rc -eq 0 ]]; then
  hyprctl reload 2>/dev/null || true
fi
exit $rc
