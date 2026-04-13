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
HYPRLAND_CONF="${HYPR_DIR}/hyprland.conf"
STATE_FILE="${HYPR_DIR}/.cloud-center-state.json"

python3 - "$MODE" "$ARG1" "$ARG2" "$STATE_FILE" "$USER_CONF" "$ANIM_CONF" "$INPUT_CONF" "$HYPRLAND_CONF" <<'PYEOF'
import sys, json, os, re, shutil
from pathlib import Path
from collections import defaultdict

mode            = sys.argv[1]
arg1            = sys.argv[2]
arg2            = sys.argv[3]
state_path      = sys.argv[4]
conf_path       = sys.argv[5]   # user_lookandfeel.conf
anim_conf_path  = sys.argv[6]   # user_animations.conf
input_conf_path = sys.argv[7]   # user_input.conf
hyprland_path   = sys.argv[8]

HYPR_DIR   = Path(hyprland_path).parent
SOURCE_DIR = HYPR_DIR / "source"
USER_DIR   = HYPR_DIR / "user-configs"
home       = str(Path.home())

# Maps each user-conf path → its counterpart filename in source/
CONF_SOURCE_MAP = {
    conf_path:       "lookandfeel.conf",
    anim_conf_path:  "animations.conf",
    input_conf_path: "input.conf",
}

_CC_BEGIN = "# --- Cloud Center Overrides (managed by hypr_persist.sh) ---"
_CC_END   = "# --- End Cloud Center Overrides ---"

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
}

# ── Load and mutate persisted state ──────────────────────────────────────────

state = {}
try:
    state = json.loads(Path(state_path).read_text(encoding="utf-8"))
except (FileNotFoundError, json.JSONDecodeError):
    pass

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


def build_override_block(sections: list[str]) -> str:
    """Build the Cloud Center override block (between markers) for given sections."""
    lines: list[str] = []
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
    return "\n".join(lines)


def strip_cc_block(text: str) -> str:
    """Remove the existing Cloud Center override block (including markers) from text."""
    pattern = (
        r"\n?" + re.escape(_CC_BEGIN) + r".*?" + re.escape(_CC_END) + r"[ \t]*\n?"
    )
    return re.sub(pattern, "", text, flags=re.DOTALL)


def write_conf(user_path_str: str, sections: list[str]) -> None:
    """Write (or update) a user conf file: source copy + CC override block."""
    user_path = Path(user_path_str)
    USER_DIR.mkdir(parents=True, exist_ok=True)

    source_name = CONF_SOURCE_MAP.get(user_path_str)
    source_path = SOURCE_DIR / source_name if source_name else None

    # Build override block (may be empty if all settings were reset)
    override_content = build_override_block(sections)

    if source_path and source_path.exists():
        # First run: copy the source file as the base
        if not user_path.exists():
            shutil.copy2(source_path, user_path)
            print(f"[hypr_persist] copied {source_path} → {user_path}")
        base = strip_cc_block(user_path.read_text(encoding="utf-8"))
    else:
        # No source file — standalone override file
        if user_path.exists():
            base = strip_cc_block(user_path.read_text(encoding="utf-8"))
        else:
            base = ""

    if override_content.strip():
        new_text = base.rstrip() + f"\n{_CC_BEGIN}\n{override_content}{_CC_END}\n"
    else:
        # Nothing to override — write clean base (or empty file)
        new_text = base.rstrip() + "\n" if base.strip() else ""

    tmp_path = user_path_str + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        f.write(new_text)
    os.replace(tmp_path, user_path_str)
    print(f"[hypr_persist] wrote {user_path_str}")


write_conf(conf_path,       ["general", "decoration"])
write_conf(anim_conf_path,  ["animations"])
write_conf(input_conf_path, ["input"])

# ── Source-line management in hyprland.conf ───────────────────────────────────
# For each user conf, find the existing "source = .../source/<name>.conf" line
# and REPLACE it with "source = ~/.config/hypr/user-configs/user_<name>.conf".
# If no such line exists, append a new source line.
# Also handle migration from the old user_cloud-center.conf name.

hyprland = Path(hyprland_path)
if not hyprland.exists():
    print(f"[hypr_persist] WARNING: {hyprland_path} not found — cannot manage source lines")
    sys.exit(0)

def _norm(p_str: str) -> str:
    """Normalise a path string: expand ~ and resolve to str for comparison."""
    return str(Path(p_str.replace("~", home)))


def _source_tilde(p: Path) -> str:
    return "~/.config/hypr/" + str(p.relative_to(HYPR_DIR))


def rewrite_source_lines(hyprland_text: str) -> str:
    """
    For each managed user conf, scan hyprland.conf lines:
    - If a source line points at the original source/<name>.conf → replace it
      with the user-configs/ path.
    - If a source line points at user_cloud-center.conf (old name) → replace
      with user_lookandfeel.conf.
    - If no existing source line found at all → append one.
    Already-correct lines are left untouched.
    """
    # Build lookup: normalised source-file path → user-conf tilde path
    replacements: dict[str, str] = {}
    for user_str, src_name in CONF_SOURCE_MAP.items():
        src_full = SOURCE_DIR / src_name
        user_tilde = _source_tilde(Path(user_str))
        # Map source/<name>.conf → user tilde
        for variant in [str(src_full), _source_tilde(src_full),
                        user_str, user_tilde]:
            replacements[_norm(variant)] = user_tilde

    # Legacy: user_cloud-center.conf → user_lookandfeel.conf
    old_uc_path = USER_DIR / "user_cloud-center.conf"
    new_uc_tilde = _source_tilde(Path(conf_path))
    for variant in [str(old_uc_path), _source_tilde(old_uc_path)]:
        replacements[_norm(variant)] = new_uc_tilde

    lines = hyprland_text.splitlines(keepends=True)
    out: list[str] = []
    replaced_confs: set[str] = set()   # user-conf tilde paths already handled

    for line in lines:
        m = re.match(r"^(\s*source\s*=\s*)(.+)", line.rstrip())
        if m:
            prefix, raw = m.group(1), m.group(2).strip()
            target = replacements.get(_norm(raw))
            if target:
                if target not in replaced_confs:
                    out.append(f"{prefix}{target}\n")
                    replaced_confs.add(target)
                    print(f"[hypr_persist] replaced source line: {raw} → {target}")
                else:
                    # Duplicate — drop it
                    print(f"[hypr_persist] removed duplicate source line: {raw}")
                continue
        out.append(line)

    # Append source lines for any user conf not yet referenced
    for user_str in [conf_path, anim_conf_path, input_conf_path]:
        user_tilde = _source_tilde(Path(user_str))
        if user_tilde not in replaced_confs:
            out.append(f"\n# Cloud Center managed config — added by hypr_persist.sh\nsource = {user_tilde}\n")
            print(f"[hypr_persist] appended source line: {user_tilde}")

    return "".join(out)


content = hyprland.read_text(encoding="utf-8")
updated = rewrite_source_lines(content)
if updated != content:
    tmp = hyprland_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(updated)
    os.replace(tmp, hyprland_path)
    print(f"[hypr_persist] updated source lines in {hyprland_path}")

# ── Migration: delete stale user_cloud-center.conf if now replaced ────────────
old_uc = USER_DIR / "user_cloud-center.conf"
if old_uc.exists() and Path(conf_path).name == "user_lookandfeel.conf":
    old_uc.unlink()
    print(f"[hypr_persist] removed legacy {old_uc}")
PYEOF

# Reload so the conf file takes effect immediately alongside hyprctl keyword
hyprctl reload 2>/dev/null || true