#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# hypr_persist.sh — persist a hyprctl keyword change across Hyprland reloads
#
# Follows the hcm config manager convention:
#   • source files live in  ~/.config/hypr/source/
#   • user overrides live in ~/.config/hypr/user-configs/user_<n>.conf
#   • hyprland.conf sources the user file instead of the original source file
#
# For each managed config file, this script:
#   1. Copies source/<name>.conf → user-configs/user_<name>.conf (if needed)
#   2. Appends a Cloud Center override block at the bottom (markers kept unique)
#   3. Replaces the "source = .../source/<name>.conf" line in hyprland.conf
#      with "source = ~/.config/hypr/user-configs/user_<name>.conf"
#      (never appends a duplicate source line)
#
# Usage:
#   hypr_persist.sh <keyword> <value>
#   hypr_persist.sh reset-page <page>
#
# e.g.:   hypr_persist.sh general:border_size 4
#         hypr_persist.sh decoration:blur:enabled true
#         hypr_persist.sh decoration:active_opacity 0.95
#         hypr_persist.sh input:kb_layout us
#         hypr_persist.sh reset-page input
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

MODE="set"
ARG1="${1:-}"
ARG2="${2:-}"

if [[ "${ARG1}" == "reset-page" ]]; then
  MODE="reset-page"
  ARG1="${2:-}"
  ARG2=""
fi

if [[ "$MODE" == "set" ]]; then
    if [[ -z "$ARG1" ]]; then
    printf 'Usage: %s <keyword> <value>\n' "$0" >&2
    exit 1
  fi
else
  if [[ -z "$ARG1" ]]; then
    printf 'Usage: %s reset-page <page>\n' "$0" >&2
    exit 1
  fi
fi

HYPR_DIR="${HOME}/.config/hypr"
USER_CONF="${HYPR_DIR}/user-configs/user_lookandfeel.conf"
ANIM_CONF="${HYPR_DIR}/user-configs/user_animations.conf"
INPUT_CONF="${HYPR_DIR}/user-configs/user_input.conf"
CURSOR_CONF="${HYPR_DIR}/user-configs/user_cursor.conf"
HYPRLAND_CONF="${HYPR_DIR}/hyprland.conf"
STATE_FILE="${HYPR_DIR}/.cloud-center-state.json"

python3 - "$MODE" "$ARG1" "$ARG2" "$STATE_FILE" "$USER_CONF" "$ANIM_CONF" "$INPUT_CONF" "$CURSOR_CONF" "$HYPRLAND_CONF" <<'PYEOF'
import sys, json, os, re
from pathlib import Path
from collections import defaultdict

mode             = sys.argv[1]
arg1             = sys.argv[2]
arg2             = sys.argv[3]
state_path       = sys.argv[4]
conf_path        = sys.argv[5]
anim_conf_path   = sys.argv[6]
input_conf_path  = sys.argv[7]
cursor_conf_path = sys.argv[8]
hyprland_path    = sys.argv[9]

# ── Keyword → Hyprland section layout ────────────────────────────────────────

LAYOUT = {
    "general:border_size":            ("general",    None,       "border_size"),
    "general:gaps_out":               ("general",    None,       "gaps_out"),
    "general:gaps_in":                ("general",    None,       "gaps_in"),
    "decoration:rounding":            ("decoration", None,       "rounding"),
    "decoration:active_opacity":      ("decoration", None,       "active_opacity"),
    "decoration:inactive_opacity":    ("decoration", None,       "inactive_opacity"),
    "decoration:blur:enabled":        ("decoration", "blur",     "enabled"),
    "decoration:blur:passes":         ("decoration", "blur",     "passes"),
    "decoration:blur:size":           ("decoration", "blur",     "size"),
    "animations:enabled":             ("animations", None,       "enabled"),
    "animations:bezier":              ("animations", None,       "bezier"),
    "animations:animation":           ("animations", None,       "animation"),
    "input:kb_layout":                ("input",      None,       "kb_layout"),
    "input:kb_variant":               ("input",      None,       "kb_variant"),
    "input:kb_model":                 ("input",      None,       "kb_model"),
    "input:kb_options":               ("input",      None,       "kb_options"),
    "input:kb_rules":                 ("input",      None,       "kb_rules"),
    "input:repeat_delay":             ("input",      None,       "repeat_delay"),
    "input:repeat_rate":              ("input",      None,       "repeat_rate"),
    "input:follow_mouse":             ("input",      None,       "follow_mouse"),
    "input:sensitivity":              ("input",      None,       "sensitivity"),
    "input:accel_profile":            ("input",      None,       "accel_profile"),
    "input:natural_scroll":           ("input",      None,       "natural_scroll"),
    "input:numlock_by_default":       ("input",      None,       "numlock_by_default"),
    "input:touchpad:natural_scroll":  ("input",      "touchpad", "natural_scroll"),
    "input:touchpad:disable_while_typing": ("input", "touchpad", "disable_while_typing"),
    "input:touchpad:tap-to-click":    ("input",      "touchpad", "tap-to-click"),
    "input:touchpad:clickfinger_behavior": ("input", "touchpad", "clickfinger_behavior"),
    "input:touchpad:middle_button_emulation": ("input", "touchpad", "middle_button_emulation"),
    "input:touchpad:scroll_factor":   ("input",      "touchpad", "scroll_factor"),
    "cursor:no_hardware_cursors":      ("cursor", None, "no_hardware_cursors"),
    "cursor:enable_hyprcursor":        ("cursor", None, "enable_hyprcursor"),
    "cursor:no_warps":                 ("cursor", None, "no_warps"),
    "cursor:persistent_warps":         ("cursor", None, "persistent_warps"),
    "cursor:warp_on_change_workspace": ("cursor", None, "warp_on_change_workspace"),
    "cursor:zoom_factor":              ("cursor", None, "zoom_factor"),
    "cursor:zoom_rigid":               ("cursor", None, "zoom_rigid"),
    "cursor:inactive_timeout":         ("cursor", None, "inactive_timeout"),
    "cursor:hide_on_key_press":        ("cursor", None, "hide_on_key_press"),
    "cursor:hide_on_touch":            ("cursor", None, "hide_on_touch"),
    "cursor:hide_on_tablet":           ("cursor", None, "hide_on_tablet"),
    "cursor:no_break_fs_vrr":          ("cursor", None, "no_break_fs_vrr"),
    "cursor:hotspot_padding":          ("cursor", None, "hotspot_padding"),
}

PAGE_KEYS = {
    "hyprland": {
        "general:border_size",
        "general:gaps_out",
        "general:gaps_in",
        "decoration:rounding",
        "decoration:active_opacity",
        "decoration:inactive_opacity",
        "decoration:blur:enabled",
        "decoration:blur:passes",
        "decoration:blur:size",
        "animations:enabled",
        "animations:bezier",
        "animations:animation",
    },
    "input": {
        "input:kb_layout",
        "input:kb_variant",
        "input:kb_model",
        "input:kb_options",
        "input:kb_rules",
        "input:repeat_delay",
        "input:repeat_rate",
        "input:follow_mouse",
        "input:sensitivity",
        "input:accel_profile",
        "input:natural_scroll",
        "input:numlock_by_default",
        "input:touchpad:natural_scroll",
        "input:touchpad:disable_while_typing",
        "input:touchpad:tap-to-click",
        "input:touchpad:clickfinger_behavior",
        "input:touchpad:middle_button_emulation",
        "input:touchpad:scroll_factor",
    },
    "cursor": {
        "cursor:no_hardware_cursors",
        "cursor:enable_hyprcursor",
        "cursor:no_warps",
        "cursor:persistent_warps",
        "cursor:warp_on_change_workspace",
        "cursor:zoom_factor",
        "cursor:zoom_rigid",
        "cursor:inactive_timeout",
        "cursor:hide_on_key_press",
        "cursor:hide_on_touch",
        "cursor:hide_on_tablet",
        "cursor:no_break_fs_vrr",
        "cursor:hotspot_padding",
    },
}

TRIPLE_TO_KEY = {v: k for k, v in LAYOUT.items()}


def parse_state_from_conf(path: Path) -> dict[str, str]:
    """Parse managed keys from an existing Hyprland conf file."""
    result: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return result
    except OSError:
        return result

    section: str | None = None
    subsection: str | None = None

    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        m_open = re.match(r"^([A-Za-z0-9_\-:]+)\s*\{$", line)
        if m_open:
            name = m_open.group(1)
            if section is None:
                section = name
            elif subsection is None:
                subsection = name
            continue

        if line == "}":
            if subsection is not None:
                subsection = None
            else:
                section = None
            continue

        m_kv = re.match(r"^([A-Za-z0-9_\-:]+)\s*=\s*(.+)$", line)
        if not m_kv or section is None:
            continue

        conf_key = m_kv.group(1)
        conf_val = m_kv.group(2).strip()
        lookup = (section, subsection, conf_key)
        key = TRIPLE_TO_KEY.get(lookup)
        if key:
            result[key] = conf_val

    return result

# ── Load and mutate persisted state (conf files are source-of-truth) ─────────

state: dict[str, str] = {}

# Read existing managed overrides from user config files.
for cfg in (Path(conf_path), Path(anim_conf_path), Path(input_conf_path), Path(cursor_conf_path)):
    state.update(parse_state_from_conf(cfg))

# For input keys, preserve distro/source values when user_input.conf is sparse.
hypr_dir = Path(input_conf_path).parents[1]
source_input_conf = hypr_dir / "source" / "input.conf"
for k, v in parse_state_from_conf(source_input_conf).items():
    if k.startswith("input:") and k not in state:
        state[k] = v

if mode == "set":
    key = arg1
    value = arg2
    if key not in LAYOUT:
        print(f"[hypr_persist] WARNING: unsupported key '{key}', skipping")
    else:
        state[key] = value
        print(f"[hypr_persist] persisted {key} = {value}")
elif mode == "reset-page":
    page = arg1
    keys = PAGE_KEYS.get(page)
    if not keys:
        print(f"[hypr_persist] ERROR: unknown page '{page}'")
        sys.exit(1)
    removed = [k for k in keys if k in state]
    for k in removed:
        state.pop(k, None)
    print(f"[hypr_persist] reset-page {page}: removed {len(removed)} override(s)")
else:
    print(f"[hypr_persist] ERROR: unknown mode '{mode}'")
    sys.exit(1)

# Keep JSON state as a compatibility/debug mirror of current conf-derived state.
Path(state_path).parent.mkdir(parents=True, exist_ok=True)
tmp = state_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(state, f, indent=2)
    f.write("\n")
os.replace(tmp, state_path)

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
input_lines = build_lines(
    "# Cloud Center — user-configs/user_input.conf",
    ["input"],
)
cursor_lines = build_lines(
    "# Cloud Center — user-configs/user_cursor.conf",
    ["cursor"],
)

write_conf(conf_path, main_lines)
write_conf(anim_conf_path, anim_lines)
write_conf(input_conf_path, input_lines)
write_conf(cursor_conf_path, cursor_lines)

print(f"[hypr_persist] wrote {conf_path}")
print(f"[hypr_persist] wrote {anim_conf_path}")
print(f"[hypr_persist] wrote {input_conf_path}")
print(f"[hypr_persist] wrote {cursor_conf_path}")

# ── Ensure hyprland.conf sources user_cloud-center.conf ──────────────────────
# Mirror the hcm TUI pattern: scan for an existing source line pointing at
# this file (in either ~ or absolute form); append one if absent.

source_specs = [
    ("~/.config/hypr/user-configs/user_cloud-center.conf", conf_path, "Cloud Center managed overrides"),
    ("~/.config/hypr/user-configs/user_animations.conf", anim_conf_path, "Cloud Center animation overrides"),
    ("~/.config/hypr/user-configs/user_input.conf", input_conf_path, "Cloud Center input overrides"),
    ("~/.config/hypr/user-configs/user_cursor.conf", cursor_conf_path, "Cloud Center cursor overrides"),
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