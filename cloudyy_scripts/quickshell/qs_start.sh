#!/usr/bin/env bash
# Canonical Quickshell start — reads Cloud Center settings (e.g. lightweight mode).
set -euo pipefail

CC_DIR="${HOME}/cloudyy_scripts/cloud-center-v2"
cd "$CC_DIR"
exec python3 -m lib.quickshell_display_settings --daemon
