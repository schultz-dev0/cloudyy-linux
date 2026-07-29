#!/usr/bin/env bash
# Shared installation support that does not own a lifecycle stage.
set -euo pipefail -E

usage() {
  printf 'Usage: %s [--help]\n\nReserved for independently rerunnable miscellaneous installer support.\n' "$(basename "$0")"
}

case "${1:-}" in
--help | -h) usage; exit 0 ;;
esac

printf '[*] No standalone other tasks are currently required.\n'
