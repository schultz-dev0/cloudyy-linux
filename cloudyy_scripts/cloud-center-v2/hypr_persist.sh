#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hypr_persist.sh — persist a hyprctl keyword change across Hyprland reloads
#
# Writes ~/.config/hypr/user-configs/user_cloud-center.conf using the same
# directory convention as the hcm config manager TUI:
#   • source files live in  ~/.config/hypr/source/
#   • user overrides live in ~/.config/hypr/user-configs/user_<n>.conf
#   • hyprland.conf sources the user file once it exists
#
# This script manages user_cloud-center.conf specifically — it holds all
# keyword overrides set via Cloud Center so they survive hyprctl reload.
# If hyprland.conf does not already source user_cloud-center.conf, a
# source line is appended automatically (same injection logic as hcm).
#
# Usage:  hypr_persist.sh <keyword> <value>
# e.g.:   hypr_persist.sh general:border_size 4
#         hypr_persist.sh decoration:blur:enabled true
#         hypr_persist.sh decoration:active_opacity 0.95
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

KEY="${1:-}"
VALUE="${2:-}"

if [[ -z "$KEY" || -z "$VALUE" ]]; then
  printf 'Usage: %s <keyword> <value>\n' "$0" >&2
  exit 1
fi

HYPR_DIR="${HOME}/.config/hypr"
USER_CONF="${HYPR_DIR}/user-configs/user_cloud-center.conf"
HYPRLAND_CONF="${HYPR_DIR}/hyprland.conf"
STATE_FILE="${HYPR_DIR}/.cloud-center-state.json"

python3 - "$KEY" "$VALUE" "$STATE_FILE" "$USER_CONF" "$HYPRLAND_CONF" <<'PYEOF'
import sys, json, os, re
from pathlib import Path
from collections import defaultdict

key           = sys.argv[1]
value         = sys.argv[2]
state_path    = sys.argv[3]
conf_path     = sys.argv[4]
hyprland_path = sys.argv[5]

# ── Load and update persisted state ──────────────────────────────────────────

state = {}
try:
    state = json.loads(Path(state_path).read_text(encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    pass

state[key] = value

Path(state_path).parent.mkdir(parents=True, exist_ok=True)
tmp = state_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, state_path)

# ── Keyword → Hyprland section layout ────────────────────────────────────────

LAYOUT = {
    "general:border_size":           ("general",     None,   "border_size"),
    "general:gaps_out":              ("general",     None,   "gaps_out"),
    "general:gaps_in":               ("general",     None,   "gaps_in"),
    "decoration:rounding":           ("decoration",  None,   "rounding"),
    "decoration:active_opacity":     ("decoration",  None,   "active_opacity"),
    "decoration:inactive_opacity":   ("decoration",  None,   "inactive_opacity"),
    "decoration:blur:enabled":       ("decoration",  "blur", "enabled"),
    "decoration:blur:passes":        ("decoration",  "blur", "passes"),
    "decoration:blur:size":          ("decoration",  "blur", "size"),
    "animations:enabled":            ("animations",  None,   "enabled"),
}

# ── Build section tree from full state ───────────────────────────────────────

top    = defaultdict(dict)
nested = defaultdict(lambda: defaultdict(dict))

for k, v in state.items():
    if k not in LAYOUT:
        continue
    section, sub, conf_key = LAYOUT[k]
    if sub:
        nested[section][sub][conf_key] = v
    else:
        top[section][conf_key] = v

# ── Write user_cloud-center.conf ──────────────────────────────────────────────

lines = [
    "# Cloud Center — user-configs/user_cloud-center.conf",
    "# Managed automatically by hypr_persist.sh — do not edit by hand.",
    "# This file is sourced by hyprland.conf and overrides distro defaults.",
    "",
]

for section in ["general", "decoration", "animations"]:
    if not top.get(section) and not nested.get(section):
        continue
    lines.append(f"{section} {{")
    for conf_key, val in top.get(section, {}).items():
        lines.append(f"    {conf_key} = {val}")
    for sub, kvs in nested.get(section, {}).items():
        lines.append(f"    {sub} {{")
        for conf_key, val in kvs.items():
            lines.append(f"        {conf_key} = {val}")
        lines.append("    }")
    lines.append("}")
    lines.append("")

Path(conf_path).parent.mkdir(parents=True, exist_ok=True)
# Create the file if it doesn't exist yet before attempting the atomic write
if not Path(conf_path).exists():
    Path(conf_path).touch()
    print(f"[hypr_persist] created {conf_path}")
tmp = conf_path + ".tmp"
with open(tmp, "w") as f:
    f.write("\n".join(lines))
os.replace(tmp, conf_path)

print(f"[hypr_persist] wrote {conf_path}  ({key} = {value})")

# ── Ensure hyprland.conf sources user_cloud-center.conf ──────────────────────
# Mirror the hcm TUI pattern: scan for an existing source line pointing at
# this file (in either ~ or absolute form); append one if absent.

source_tilde = "~/.config/hypr/user-configs/user_cloud-center.conf"
home         = str(Path.home())
source_abs   = conf_path

hyprland = Path(hyprland_path)
if not hyprland.exists():
    print(f"[hypr_persist] WARNING: {hyprland_path} not found — cannot inject source line")
    sys.exit(0)

content = hyprland.read_text(encoding="utf-8")

already = any(
    re.search(r"^\s*source\s*=\s*" + re.escape(v), content, re.MULTILINE)
    for v in [source_tilde, source_abs, source_tilde.replace("~", home)]
)

if not already:
    addition = (
        "\n# Cloud Center managed overrides — added by hypr_persist.sh\n"
        f"source = {source_tilde}\n"
    )
    tmp = hyprland_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(content + addition)
    os.replace(tmp, hyprland_path)
    print(f"[hypr_persist] injected source line into {hyprland_path}")
else:
    print(f"[hypr_persist] source line already present")
PYEOF

# Reload so the conf file takes effect immediately alongside hyprctl keyword
hyprctl reload 2>/dev/null || true