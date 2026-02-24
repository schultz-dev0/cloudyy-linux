#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# set_position.sh — Waybar position switcher
# Patches the active config.jsonc to place the bar at top, bottom, left, or right.
# Saves position to ~/.config/waybar/.current_position for state restore.
#
# Usage:
#   set_position.sh <top|bottom|left|right>
#   set_position.sh --list
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

readonly WAYBAR_DIR="${HOME}/.config/waybar"
readonly ACTIVE_CONFIG="${WAYBAR_DIR}/config.jsonc"
readonly CURRENT_POSITION_FILE="${WAYBAR_DIR}/.current_position"

die()  { printf '[set_position] ERROR: %s\n' "$*" >&2; exit 1; }
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
[[ -z "$POSITION" ]] && { printf 'Usage: %s <top|bottom|left|right>\n' "$0" >&2; exit 1; }

case "$POSITION" in
  top|bottom|left|right) ;;
  *) die "Invalid position '$POSITION'. Must be: top, bottom, left, right" ;;
esac

[[ -f "${ACTIVE_CONFIG}" ]] || die "Active config not found at ${ACTIVE_CONFIG}"

info "Applying position: ${POSITION}"

# ── Patch config via Python ────────────────────────────────────────────────
# Read the JSONC (strip // comments), patch, write back.

python3 - "$ACTIVE_CONFIG" "$POSITION" << 'PYEOF'
import sys, re, json

config_path = sys.argv[1]
position    = sys.argv[2]

with open(config_path) as f:
    raw = f.read()

# Strip single-line // comments (preserve structure)
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

cfg = json.loads(strip_comments(raw))

cfg["position"] = position

if position in ("top", "bottom"):
    # Horizontal bar — restore/set sensible margins
    # Detect if this is a floating preset (has existing non-zero margins)
    # or a full-width preset (margin-left/right == 0)
    is_floating = cfg.get("margin-left", 0) != 0 or cfg.get("margin-right", 0) != 0

    if is_floating:
        margin_edge = cfg.get("margin-top", 6) if cfg.get("margin-top", 0) != 0 else cfg.get("margin-bottom", 6)
        if margin_edge == 0:
            margin_edge = 6
    else:
        margin_edge = 0

    if position == "top":
        cfg["margin-top"]    = margin_edge
        cfg["margin-bottom"] = 0
    else:
        cfg["margin-top"]    = 0
        cfg["margin-bottom"] = margin_edge

    # Remove vertical-bar overrides if any
    cfg.pop("width", None)

elif position in ("left", "right"):
    # Vertical bar — remove height, set width, clear horizontal margins
    cfg.pop("height", None)
    cfg["width"] = 40

    cfg["margin-top"]    = 6
    cfg["margin-bottom"] = 6

    if position == "left":
        cfg["margin-left"]  = 6
        cfg["margin-right"] = 0
    else:
        cfg["margin-left"]  = 0
        cfg["margin-right"] = 6

# Write back (pretty-printed, no trailing whitespace)
output = json.dumps(cfg, indent=2, ensure_ascii=False)
with open(config_path, 'w') as f:
    f.write(output + '\n')

print(f"[set_position] Patched {config_path} → position: {position}")
PYEOF

echo "${POSITION}" > "${CURRENT_POSITION_FILE}"
info "Position saved. Run launch_waybar.sh to apply."

# ─────────────────────────────────────────────────────────────────────────────
# Restart is done by the caller (Cloud Center chains: set_position.sh <pos> && launch_waybar.sh)
