#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hypr_persist.sh — persist a hyprctl keyword change across Hyprland reloads
#
# Writes Cloud Center managed files in ~/.config/hypr/user-configs using the same
# directory convention as the hcm config manager TUI:
#   • source files live in  ~/.config/hypr/source/
#   • user overrides live in ~/.config/hypr/user-configs/user_<n>.conf
#   • hyprland.conf sources the user file once it exists
#
# This script manages Cloud Center keyword override files so they survive
# hyprctl reload. If hyprland.conf does not already source user_*.conf files,
# source lines are appended automatically (same injection logic as hcm).
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
ANIM_CONF="${HYPR_DIR}/user-configs/user_animations.conf"
HYPRLAND_CONF="${HYPR_DIR}/hyprland.conf"
STATE_FILE="${HYPR_DIR}/.cloud-center-state.json"

python3 - "$KEY" "$VALUE" "$STATE_FILE" "$USER_CONF" "$ANIM_CONF" "$HYPRLAND_CONF" <<'PYEOF'
import sys, json, os, re
from pathlib import Path
from collections import defaultdict

key           = sys.argv[1]
value         = sys.argv[2]
state_path    = sys.argv[3]
conf_path     = sys.argv[4]
anim_conf_path = sys.argv[5]
hyprland_path = sys.argv[6]

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
    "animations:bezier":             ("animations",  None,   "bezier"),
    "animations:animation":          ("animations",  None,   "animation"),
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

def build_lines(title: str, sections: list[str]) -> list[str]:
    lines = [
        title,
        "# Managed automatically by hypr_persist.sh — do not edit by hand.",
        "# This file is sourced by hyprland.conf and overrides distro defaults.",
        "",
    ]

    for section in sections:
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
    return lines


def write_conf(path: str, lines: list[str]) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    if not Path(path).exists():
        Path(path).touch()
        print(f"[hypr_persist] created {path}")
    tmp_path = path + ".tmp"
    with open(tmp_path, "w") as f:
        f.write("\n".join(lines))
    os.replace(tmp_path, path)


main_lines = build_lines(
    "# Cloud Center — user-configs/user_cloud-center.conf",
    ["general", "decoration"],
)
anim_lines = build_lines(
    "# Cloud Center — user-configs/user_animations.conf",
    ["animations"],
)

write_conf(conf_path, main_lines)
write_conf(anim_conf_path, anim_lines)

print(f"[hypr_persist] wrote {conf_path}  ({key} = {value})")
print(f"[hypr_persist] wrote {anim_conf_path}  ({key} = {value})")

# ── Ensure hyprland.conf sources user_cloud-center.conf ──────────────────────
# Mirror the hcm TUI pattern: scan for an existing source line pointing at
# this file (in either ~ or absolute form); append one if absent.

source_specs = [
    ("~/.config/hypr/user-configs/user_cloud-center.conf", conf_path, "Cloud Center managed overrides"),
    ("~/.config/hypr/user-configs/user_animations.conf", anim_conf_path, "Cloud Center animation overrides"),
]
home = str(Path.home())

hyprland = Path(hyprland_path)
if not hyprland.exists():
    print(f"[hypr_persist] WARNING: {hyprland_path} not found — cannot inject source line")
    sys.exit(0)

content = hyprland.read_text(encoding="utf-8")
updated = content
injected_any = False

for source_tilde, source_abs, comment in source_specs:
    already = any(
        re.search(r"^\s*source\s*=\s*" + re.escape(v), updated, re.MULTILINE)
        for v in [source_tilde, source_abs, source_tilde.replace("~", home)]
    )
    if already:
        print(f"[hypr_persist] source line already present: {source_tilde}")
        continue
    updated += (
        f"\n# {comment} — added by hypr_persist.sh\n"
        f"source = {source_tilde}\n"
    )
    injected_any = True

# Also ensure every existing user_*.conf file is sourced.
user_dir = Path(conf_path).parent
for p in sorted(user_dir.glob("user_*.conf")):
    source_tilde = f"~/.config/hypr/user-configs/{p.name}"
    source_abs = str(p)
    already = any(
        re.search(r"^\s*source\s*=\s*" + re.escape(v), updated, re.MULTILINE)
        for v in [source_tilde, source_abs, source_tilde.replace("~", home)]
    )
    if already:
        continue
    updated += (
        "\n# Cloud Center auto-sourced user config — added by hypr_persist.sh\n"
        f"source = {source_tilde}\n"
    )
    injected_any = True

if injected_any:
    tmp = hyprland_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(updated)
    os.replace(tmp, hyprland_path)
    print(f"[hypr_persist] injected source line(s) into {hyprland_path}")
PYEOF

# Reload so the conf file takes effect immediately alongside hyprctl keyword
hyprctl reload 2>/dev/null || true