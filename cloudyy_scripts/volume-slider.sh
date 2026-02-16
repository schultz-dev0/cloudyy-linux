#!/usr/bin/env bash
#
# universal slider manager thingy
#

set -euo pipefail

# ==============================================================================
# CONFIGURATION
# ==============================================================================
readonly VOLUME_STEP=5

# ==============================================================================
# COMMAND HANDLING
# ==============================================================================

if ! pgrep -x "swayosd-server" >/dev/null; then
  echo "Starting swayosd-server..."
  swayosd-server &
  sleep 0.1
fi

case "${1:-show}" in
up)
  swayosd-client --output-volume "+${VOLUME_STEP}"
  ;;
down)
  swayosd-client --output-volume "-${VOLUME_STEP}"
  ;;
mute)
  swayosd-client --output-volume mute-toggle
  ;;
set)
  # Handle "set 50" or just "50"
  val="${2:-50}"
  swayosd-client --output-volume "$val"
  ;;
*)
  echo "Usage: $0 {up|down|mute|set <val>}"
  exit 1
  ;;
esac

exit 0
