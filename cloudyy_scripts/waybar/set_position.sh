#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# set_position.sh — Waybar position switcher (Atomic Fix)
# Patches the active config.jsonc to place the bar at top, bottom, left, or right.
# Uses atomic writes to prevent Waybar from reading an empty file during reload.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

readonly WAYBAR_DIR="${HOME}/.config/waybar"
readonly ACTIVE_CONFIG="${WAYBAR_DIR}/config.jsonc"
readonly CURRENT_POSITION_FILE="${WAYBAR_DIR}/.current_position"
readonly VERTICAL_SIDE_FILE="${WAYBAR_DIR}/.vertical_side"

die() {
  printf '[set_position] ERROR: %s\n' "$*" >&2
  exit 1
}
info() { printf '[set_position] %s\n' "$*" >&2; }

# ── Argument handling ──────────────────────────────────────────────────────

if [[ "${1:-}" == "--list" ]]; then
  current="$(cat "${CURRENT_POSITION_FILE}" 2>/dev/null || echo top)"
  for pos in top bottom left right; do
    marker=""
    [[ "$pos" == "$current" ]] && marker=" (active)"
    printf '  • %s%s\n' "$pos" "$marker" >&2
  done
  exit 0
fi

POSITION="${1:-}"
[[ -z "$POSITION" ]] && {
  printf 'Usage: %s <top|bottom|left|right>\n' "$0" >&2
  exit 1
}

case "$POSITION" in
top | bottom | left | right) ;;
*) die "Invalid position '$POSITION'. Must be: top, bottom, left, right" ;;
esac

[[ -f "${ACTIVE_CONFIG}" ]] || die "Active config not found at ${ACTIVE_CONFIG}"

info "Applying position: ${POSITION}"

# ── Patch config via Python (Atomic) ───────────────────────────────────────

python3 - "$ACTIVE_CONFIG" "$POSITION" <<'PYEOF'
import sys, re, json, os

config_path = sys.argv[1]
position    = sys.argv[2]

# Read existing config
with open(config_path, 'r') as f:
    raw = f.read()

def strip_comments(text):
    result = []
    in_string = False
    i = 0
    while i < len(text):
        c = text[i]
        if c == '"' and (i == 0 or text[i-1] != '\\'):
            in_string = not in_string
        if not in_string and c == '/' and i + 1 < len(text) and text[i+1] == '/':
            while i < len(text) and text[i] != '\n':
                i += 1
            continue
        result.append(c)
        i += 1
    return ''.join(result)

try:
    cfg = json.loads(strip_comments(raw))
except json.JSONDecodeError as e:
    print(f"Error decoding JSON: {e}")
    sys.exit(1)

cfg["position"] = position

# Adjust margins based on position
if position in ("top", "bottom"):
    # Check if there were side margins indicating a floating bar
    is_floating = cfg.get("margin-left", 0) != 0 or cfg.get("margin-right", 0) != 0
    
    # Heuristic: If it was vertical with margins, preserve margin "thickness" for top/bottom
    if is_floating:
        # Grab existing margin or default to 6
        margin_edge = cfg.get("margin-top", 0) or cfg.get("margin-bottom", 0) or 6
    else:
        margin_edge = 0

    if position == "top":
        cfg["margin-top"]    = margin_edge
        cfg["margin-bottom"] = 0
    else:
        cfg["margin-top"]    = 0
        cfg["margin-bottom"] = margin_edge

    # Remove width restriction for horizontal bars (allow full width or auto)
    cfg.pop("width", None)

elif position in ("left", "right"):
    # Remove height restriction for vertical bars
    cfg.pop("height", None)

    # Preserve the preset's own width if it specified one;
    # only fall back to the generic default when no width is present.
    # (set_position.sh is called AFTER switch_style.sh copies the preset
    #  config, so the width here is already the preset's intended value.)
    if "width" not in cfg:
        cfg["width"] = 46

    # Add standard vertical margins
    cfg["margin-top"]    = 6
    cfg["margin-bottom"] = 6

    if position == "left":
        cfg["margin-left"]  = 6
        cfg["margin-right"] = 0
    else:
        cfg["margin-left"]  = 0
        cfg["margin-right"] = 6

# ── ATOMIC WRITE FIX ──────────────────────────────────────────────────────
# Write to a temp file first, then rename. 
# This prevents Waybar from reading a truncated (empty) file during reload.

output = json.dumps(cfg, indent=4, ensure_ascii=False)
tmp_path = config_path + ".tmp"

with open(tmp_path, 'w') as f:
    f.write(output + '\n')

os.replace(tmp_path, config_path)
print(f"[set_position] Patched {config_path} → position: {position}")
PYEOF

echo "${POSITION}" >"${CURRENT_POSITION_FILE}"

# Also persist left/right as the preferred vertical side
if [[ "${POSITION}" == "left" || "${POSITION}" == "right" ]]; then
  echo "${POSITION}" >"${VERTICAL_SIDE_FILE}"
  info "Vertical side saved: ${POSITION}"
fi

info "Position saved."
