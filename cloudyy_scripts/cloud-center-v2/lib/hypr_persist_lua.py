from __future__ import annotations

import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

from lib.hyprlua_runtime import archive_legacy_conf_tree, ensure_source_active, ensure_user_override_active

LAYOUT = {
    "general:border_size": ("general", None, "border_size"),
    "general:gaps_out": ("general", None, "gaps_out"),
    "general:gaps_in": ("general", None, "gaps_in"),
    "decoration:rounding": ("decoration", None, "rounding"),
    "decoration:active_opacity": ("decoration", None, "active_opacity"),
    "decoration:inactive_opacity": ("decoration", None, "inactive_opacity"),
    "decoration:shadow:enabled": ("decoration", "shadow", "enabled"),
    "decoration:shadow:range": ("decoration", "shadow", "range"),
    "decoration:shadow:render_power": ("decoration", "shadow", "render_power"),
    "decoration:blur:enabled": ("decoration", "blur", "enabled"),
    "decoration:blur:passes": ("decoration", "blur", "passes"),
    "decoration:blur:size": ("decoration", "blur", "size"),
    "animations:enabled": ("animations", None, "enabled"),
    "animations:bezier": ("animations", None, "bezier"),
    "animations:animation": ("animations", None, "animation"),
    "input:kb_layout": ("input", None, "kb_layout"),
    "input:kb_variant": ("input", None, "kb_variant"),
    "input:kb_model": ("input", None, "kb_model"),
    "input:kb_options": ("input", None, "kb_options"),
    "input:kb_rules": ("input", None, "kb_rules"),
    "input:repeat_delay": ("input", None, "repeat_delay"),
    "input:repeat_rate": ("input", None, "repeat_rate"),
    "input:follow_mouse": ("input", None, "follow_mouse"),
    "input:sensitivity": ("input", None, "sensitivity"),
    "input:accel_profile": ("input", None, "accel_profile"),
    "input:natural_scroll": ("input", None, "natural_scroll"),
    "input:numlock_by_default": ("input", None, "numlock_by_default"),
    "input:touchpad:natural_scroll": ("input", "touchpad", "natural_scroll"),
    "input:touchpad:disable_while_typing": ("input", "touchpad", "disable_while_typing"),
    "input:touchpad:tap-to-click": ("input", "touchpad", "tap-to-click"),
    "input:touchpad:clickfinger_behavior": ("input", "touchpad", "clickfinger_behavior"),
    "input:touchpad:middle_button_emulation": ("input", "touchpad", "middle_button_emulation"),
    "input:touchpad:scroll_factor": ("input", "touchpad", "scroll_factor"),
    "cursor:no_hardware_cursors": ("cursor", None, "no_hardware_cursors"),
    "cursor:enable_hyprcursor": ("cursor", None, "enable_hyprcursor"),
    "cursor:no_warps": ("cursor", None, "no_warps"),
    "cursor:persistent_warps": ("cursor", None, "persistent_warps"),
    "cursor:warp_on_change_workspace": ("cursor", None, "warp_on_change_workspace"),
    "cursor:zoom_factor": ("cursor", None, "zoom_factor"),
    "cursor:zoom_rigid": ("cursor", None, "zoom_rigid"),
    "cursor:inactive_timeout": ("cursor", None, "inactive_timeout"),
    "cursor:hide_on_key_press": ("cursor", None, "hide_on_key_press"),
    "cursor:hide_on_touch": ("cursor", None, "hide_on_touch"),
    "cursor:hide_on_tablet": ("cursor", None, "hide_on_tablet"),
    "cursor:no_break_fs_vrr": ("cursor", None, "no_break_fs_vrr"),
    "cursor:hotspot_padding": ("cursor", None, "hotspot_padding"),
}

PAGE_KEYS = {
    "hyprland": {
        "general:border_size",
        "general:gaps_out",
        "general:gaps_in",
        "decoration:rounding",
        "decoration:active_opacity",
        "decoration:inactive_opacity",
        "decoration:shadow:enabled",
        "decoration:shadow:range",
        "decoration:shadow:render_power",
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

SURFACE_FILES = {
    "lookandfeel": "user_lookandfeel.lua",
    "animations": "user_animations.lua",
    "input": "user_input.lua",
    "cursor": "user_cursor.lua",
}

SURFACE_SECTIONS = {
    "lookandfeel": ("general", "decoration"),
    "animations": ("animations",),
    "input": ("input",),
    "cursor": ("cursor",),
}

SOURCE_SURFACES = {"lookandfeel", "animations", "input"}
SECTION_TO_SURFACE = {
    "general": "lookandfeel",
    "decoration": "lookandfeel",
    "animations": "animations",
    "input": "input",
    "cursor": "cursor",
}
LEGACY_CONF_FILES = {
    "lookandfeel": "user_lookandfeel.conf",
    "animations": "user_animations.conf",
    "input": "user_input.conf",
    "cursor": "user_cursor.conf",
}
MANAGED_STATE_PREFIX = "-- @cloud-center-state = "
NUMBER_RE = re.compile(r"^-?(?:\d+\.\d+|\d+|\.\d+)$")
LUA_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
TRIPLE_TO_KEY = {v: k for k, v in LAYOUT.items()}


def parse_args(argv: list[str]) -> tuple[str, str, str, Path | None]:
    arg1 = argv[1] if len(argv) > 1 else ""
    arg2 = argv[2] if len(argv) > 2 else ""
    arg3 = argv[3] if len(argv) > 3 else ""

    if arg1 == "reset-page":
        if not arg2:
            raise ValueError(f"Usage: {argv[0]} reset-page <page> [hypr_dir]")
        return "reset-page", arg2, "", Path(arg3).expanduser() if arg3 else None

    if not arg1:
        raise ValueError(f"Usage: {argv[0]} <keyword> <value> [hypr_dir]")
    return "set", arg1, arg2, Path(arg3).expanduser() if arg3 else None


def parse_state_from_conf(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return result

    section: str | None = None
    subsection: str | None = None
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        match_open = re.match(r"^([A-Za-z0-9_\-:]+)\s*\{$", line)
        if match_open:
            name = match_open.group(1)
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

        match_kv = re.match(r"^([A-Za-z0-9_\-:]+)\s*=\s*(.+)$", line)
        if not match_kv or section is None:
            continue

        lookup = (section, subsection, match_kv.group(1))
        key = TRIPLE_TO_KEY.get(lookup)
        if key:
            result[key] = match_kv.group(2).strip()

    return result


def parse_state_from_lua(path: Path) -> tuple[bool, dict[str, str]]:
    try:
        for line in path.read_text(encoding="utf-8").splitlines()[:5]:
            if line.startswith(MANAGED_STATE_PREFIX):
                data = json.loads(line[len(MANAGED_STATE_PREFIX):])
                if isinstance(data, dict):
                    return True, {str(k): str(v) for k, v in data.items() if k in LAYOUT}
    except (OSError, json.JSONDecodeError):
        pass
    return False, {}


def load_state(hypr_dir: Path) -> dict[str, str]:
    user_dir = hypr_dir / "user-configs"
    lua_state: dict[str, str] = {}
    has_managed_lua_state = False

    for surface, name in SURFACE_FILES.items():
        present, parsed = parse_state_from_lua(user_dir / name)
        has_managed_lua_state = has_managed_lua_state or present
        lua_state.update(parsed)

    state_path = hypr_dir / ".cloud-center-state.json"
    try:
        data = json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        data = None

    if has_managed_lua_state or isinstance(data, dict):
        state: dict[str, str] = {}
        if isinstance(data, dict):
            state.update({str(k): str(v) for k, v in data.items() if k in LAYOUT})
        state.update(lua_state)
        return state

    state: dict[str, str] = {}
    for surface, name in LEGACY_CONF_FILES.items():
        state.update(parse_state_from_conf(user_dir / name))

    return state


def lua_key(key: str) -> str:
    if LUA_IDENTIFIER_RE.match(key):
        return key
    return f"[{json.dumps(key)}]"

def save_state(path: Path, state: dict[str, str]) -> None:
    atomic_write(path, json.dumps(state, indent=2) + "\n")


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(content, encoding="utf-8")
    os.replace(tmp, path)


def surface_for_key(key: str) -> str | None:
    layout = LAYOUT.get(key)
    return None if layout is None else SECTION_TO_SURFACE[layout[0]]


def quote(value: str) -> str:
    if value in {"true", "false"}:
        return value
    if NUMBER_RE.match(value):
        return value
    return json.dumps(value)


def _nested_values(state: dict[str, str], surface: str) -> tuple[dict[str, dict[str, str]], dict[str, dict[str, dict[str, str]]]]:
    top: dict[str, dict[str, str]] = defaultdict(dict)
    nested: dict[str, dict[str, dict[str, str]]] = defaultdict(lambda: defaultdict(dict))
    for key in LAYOUT:
        if key not in state or surface_for_key(key) != surface:
            continue
        section, sub, config_key = LAYOUT[key]
        if sub is None:
            top[section][config_key] = state[key]
        else:
            nested[section][sub][config_key] = state[key]
    return top, nested


def render_config_blocks(state: dict[str, str], surface: str) -> list[str]:
    top, nested = _nested_values(state, surface)
    sections = SURFACE_SECTIONS[surface]
    if not any(top.get(section) or nested.get(section) for section in sections):
        return []

    lines = ["hl.config({"]
    for section in sections:
        if not top.get(section) and not nested.get(section):
            continue
        lines.append(f"    {section} = {{")
        for config_key, value in top.get(section, {}).items():
            lines.append(f"        {lua_key(config_key)} = {quote(value)},")
        for sub, sub_values in nested.get(section, {}).items():
            lines.append(f"        {sub} = {{")
            for config_key, value in sub_values.items():
                lines.append(f"            {lua_key(config_key)} = {quote(value)},")
            lines.append("        },")
        lines.append("    },")
    lines.append("})")
    return lines


def render_animation_curve(value: str) -> str | None:
    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 5:
        return None
    name, x1, y1, x2, y2 = parts
    return (
        f"hl.curve({quote(name)}, {{ type = \"bezier\", points = {{ {{ {x1}, {y1} }}, {{ {x2}, {y2} }} }} }})"
    )


def render_animation(value: str) -> str | None:
    parts = [part.strip() for part in value.split(",")]
    if len(parts) < 4:
        return None
    leaf, enabled, speed, bezier, *style = parts
    enabled_lua = "true" if enabled in {"1", "true"} else "false"
    fields = [
        f"leaf = {quote(leaf)}",
        f"enabled = {enabled_lua}",
        f"speed = {quote(speed)}",
        f"bezier = {quote(bezier)}",
    ]
    if style:
        fields.append(f"style = {quote(','.join(style))}")
    return f"hl.animation({{ {', '.join(fields)} }})"


def build_surface_content(state: dict[str, str], surface: str) -> str:
    surface_state = {key: state[key] for key in LAYOUT if key in state and surface_for_key(key) == surface}
    lines = [
        f"-- Cloud Center user override file for {surface} configuration.",
        f"{MANAGED_STATE_PREFIX}{json.dumps(surface_state, sort_keys=True)}",
    ]
    if surface in SOURCE_SURFACES:
        lines.extend(["", f'require("source.{surface}")'])

    body: list[str] = []
    if surface == "animations":
        if "animations:enabled" in surface_state:
            body.append(f"hl.config({{ animations = {{ enabled = {quote(surface_state['animations:enabled'])} }} }})")
        if "animations:bezier" in surface_state:
            curve = render_animation_curve(surface_state["animations:bezier"])
            if curve:
                body.append(curve)
        if "animations:animation" in surface_state:
            animation = render_animation(surface_state["animations:animation"])
            if animation:
                body.append(animation)
    else:
        body.extend(render_config_blocks(surface_state, surface))

    if body:
        lines.extend(["", *body])
    return "\n".join(lines) + "\n"


def write_surface_files(hypr_dir: Path, state: dict[str, str], surfaces: set[str] | None = None) -> None:
    user_dir = hypr_dir / "user-configs"
    user_dir.mkdir(parents=True, exist_ok=True)
    target_surfaces = surfaces or set(SURFACE_FILES)
    for surface in target_surfaces:
        filename = SURFACE_FILES[surface]
        path = user_dir / filename
        has_surface_overrides = any(surface_for_key(key) == surface for key in state)
        if has_surface_overrides:
            atomic_write(path, build_surface_content(state, surface))
            print(f"[hypr_persist] wrote {path}")
        elif path.exists():
            path.unlink()
            print(f"[hypr_persist] removed {path}")


def update_activation(hypr_dir: Path, state: dict[str, str], surfaces: set[str] | None = None) -> None:
    hyprland_path = hypr_dir / "hyprland.lua"
    if not hyprland_path.exists():
        print(f"[hypr_persist] WARNING: {hyprland_path} not found — cannot update activation lines")
        return

    updated = hyprland_path.read_text(encoding="utf-8")
    for surface in (surfaces or set(SURFACE_FILES)):
        has_surface_overrides = any(surface_for_key(key) == surface for key in state)
        if has_surface_overrides:
            updated = ensure_user_override_active(updated, surface)
        else:
            updated = ensure_source_active(updated, surface)
    atomic_write(hyprland_path, updated)
    print(f"[hypr_persist] updated activation lines in {hyprland_path}")


def main(argv: list[str]) -> int:
    try:
        mode, arg1, arg2, hypr_dir_override = parse_args(argv)
    except ValueError as exc:
        print(exc, file=sys.stderr)
        return 1

    hypr_dir = hypr_dir_override or (Path.home() / ".config" / "hypr")
    state = load_state(hypr_dir)
    touched_surfaces: set[str] = set()

    if mode == "set":
        if arg1 not in LAYOUT:
            print(f"[hypr_persist] WARNING: unsupported key '{arg1}', skipping")
            return 0
        state[arg1] = arg2
        surface = surface_for_key(arg1)
        if surface:
            touched_surfaces.add(surface)
        print(f"[hypr_persist] persisted {arg1} = {arg2}")
    elif mode == "reset-page":
        keys = PAGE_KEYS.get(arg1)
        if not keys:
            print(f"[hypr_persist] ERROR: unknown page '{arg1}'")
            return 1
        touched_surfaces = {surface for key in keys if (surface := surface_for_key(key)) is not None}
        removed = [key for key in keys if key in state]
        for key in removed:
            state.pop(key, None)
        print(f"[hypr_persist] reset-page {arg1}: removed {len(removed)} override(s)")
    else:
        print(f"[hypr_persist] ERROR: unknown mode '{mode}'")
        return 1

    save_state(hypr_dir / ".cloud-center-state.json", state)
    write_surface_files(hypr_dir, state, touched_surfaces)
    update_activation(hypr_dir, state, touched_surfaces)
    archive_legacy_conf_tree(hypr_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
