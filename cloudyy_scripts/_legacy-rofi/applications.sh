#!/usr/bin/env bash
# =============================================================================
# applications.sh — Application Launcher (rofi drun)
# =============================================================================

set -uo pipefail

rofi -show drun \
  -theme-str 'listview { columns: 4; lines: 6; }' \
  -theme-str 'element { orientation: vertical; children: [ element-icon, element-text ]; padding: 10px; }' \
  -theme-str 'element-icon { size: 64px; horizontal-align: 0.5; }' \
  -theme-str 'element-text { horizontal-align: 0.5; }' \
  -show-icons
