#!/usr/bin/env bash
# Compatibility entry point; apps now come from the shared in-memory catalog.
set -euo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/search-files.py" "${1:-}"
