#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
#  wlogout-launch - Dynamic Scaling & Theming (PNG Icons Version)
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# 1. Configuration & Constants
# ──────────────────────────────────────────────────────────────
# We use ~/.config because 'stow' links your dotfiles here.
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/wlogout"
readonly LAYOUT_FILE="${CONFIG_DIR}/layout"
readonly ICONS_DIR="$HOME/dots/.config/wlogout/icons"
readonly MATUGEN_COLORS="${XDG_CONFIG_HOME:-$HOME/.config}/matugen/generated/colors.css"
readonly TMP_CSS="/tmp/wlogout-${UID}.css"

# Scaling Settings (1080p Reference)
readonly REF_HEIGHT=1080
readonly BASE_ICON_SIZE=100 # Base size for PNG icons
readonly BASE_BUTTON_RAD=20
readonly BASE_ACTIVE_RAD=25
readonly BASE_MARGIN=60
readonly BASE_HOVER_OFFSET=15
readonly BASE_COL_SPACING=5

# ──────────────────────────────────────────────────────────────
# 2. Safety Checks
# ──────────────────────────────────────────────────────────────
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "ERROR: Not running inside Hyprland." >&2
  exit 1
fi

# Check if Matugen colors exist
if [[ ! -f "$MATUGEN_COLORS" ]]; then
  echo "ERROR: Mutagen colors not found at $MATUGEN_COLORS" >&2
  exit 1
fi

# Check if icons directory exists
if [[ ! -d "$ICONS_DIR" ]]; then
  echo "ERROR: Icons directory not found at $ICONS_DIR" >&2
  exit 1
fi

# Toggle: Kill if running
if pkill -x "wlogout"; then
  exit 0
fi

trap 'rm -f "$TMP_CSS"' EXIT

# ──────────────────────────────────────────────────────────────
# 3. Dynamic Scaling Logic
# ──────────────────────────────────────────────────────────────
# Get Monitor Resolution & Scale
MON_DATA=$(hyprctl monitors -j 2>/dev/null | jq -r '
    (first(.[] | select(.focused)) // .[0] // {height: 1080, scale: 1}) 
    | "\(.height) \(.scale)"
')

read -r HEIGHT SCALE <<<"${MON_DATA:-1080 1}"

# Calculate scaling ratio
CALC_VARS=$(awk -v h="$HEIGHT" -v s="$SCALE" -v rh="$REF_HEIGHT" \
  -v i="$BASE_ICON_SIZE" -v br="$BASE_BUTTON_RAD" \
  -v ar="$BASE_ACTIVE_RAD" -v m="$BASE_MARGIN" \
  -v ho="$BASE_HOVER_OFFSET" -v cs="$BASE_COL_SPACING" '
BEGIN {
    ratio = (h / s) / rh;
    if (ratio < 0.5) ratio = 0.5;
    if (ratio > 2.0) ratio = 2.0;
    
    printf "%d %d %d %d %d %d", 
        int(i * ratio), int(br * ratio), int(ar * ratio), 
        int(m * ratio), int(ho * ratio), int(cs * ratio)
}')

read -r ICON_SIZE BTN_RAD ACT_RAD MARGIN HOVER_OFFSET COL_SPACING <<<"$CALC_VARS"
HOVER_MARGIN=$((MARGIN - HOVER_OFFSET))

# ──────────────────────────────────────────────────────────────
# 4. CSS Generation (With PNG Icons)
# ──────────────────────────────────────────────────────────────
cat >"$TMP_CSS" <<EOF
/* Import Mutagen Colors */
@import url("file://${MATUGEN_COLORS}");

window {
    background-color: rgba(0, 0, 0, 0.6);
}

button {
    /* Matugen Colors */
    background-color: @secondary_container;
    color: @on_secondary_container;
    
    border: 2px solid @outline;
    border-radius: ${BTN_RAD}px;
    outline-style: none;
    
    /* Icon Settings */
    background-repeat: no-repeat;
    background-position: center;
    background-size: ${ICON_SIZE}px ${ICON_SIZE}px;
    box-shadow: none;
    margin: 0px;

    transition: 
        background-color 0.2s ease,
        color 0.2s ease,
        border-radius 0.2s ease,
        margin 0.2s ease;
}

button:focus {
    background-color: @tertiary_container;
    color: @on_tertiary_container;
}

button:hover {
    background-color: @primary;
    color: @on_primary;
    border-radius: ${ACT_RAD}px;
}

/* ──────────────────────────────────────────────────────────────
   Icon Mappings (PNG Images)
   ────────────────────────────────────────────────────────────── */

/* Lock */
#lock { 
    background-image: url("file://${ICONS_DIR}/lock.png");
    margin: ${MARGIN}px 0; 
}
button:hover#lock { margin: ${HOVER_MARGIN}px 0; }

/* Logout */
#logout { 
    background-image: url("file://${ICONS_DIR}/logout.png");
    margin: ${MARGIN}px 0; 
}
button:hover#logout { margin: ${HOVER_MARGIN}px 0; }

/* Suspend */
#suspend { 
    background-image: url("file://${ICONS_DIR}/suspend.png");
    margin: ${MARGIN}px 0; 
}
button:hover#suspend { margin: ${HOVER_MARGIN}px 0; }

/* Reboot */
#reboot { 
    background-image: url("file://${ICONS_DIR}/reboot.png");
    margin: ${MARGIN}px 0; 
}
button:hover#reboot { margin: ${HOVER_MARGIN}px 0; }

/* Shutdown */
#shutdown { 
    background-image: url("file://${ICONS_DIR}/shutdown.png");
    margin: ${MARGIN}px 0; 
}
button:hover#shutdown { margin: ${HOVER_MARGIN}px 0; }

EOF

# ──────────────────────────────────────────────────────────────
# 5. Launch
# ──────────────────────────────────────────────────────────────
wlogout \
  --layout "$LAYOUT_FILE" \
  --css "$TMP_CSS" \
  --protocol layer-shell \
  --buttons-per-row 5 \
  --column-spacing "$COL_SPACING" \
  --row-spacing 0 \
  "$@"
