"""Pure monitor-layout parsing, geometry, and Lua serialization helpers."""
from __future__ import annotations

import re
from typing import Any, Iterable


STRING_FIELDS = {
    "output", "mode", "position", "scale", "mirror", "cm", "sdr_eotf", "icc",
}
INTEGER_FIELDS = {
    "transform", "bitdepth", "vrr", "supports_wide_color", "supports_hdr",
    "sdr_max_luminance", "max_luminance", "max_avg_luminance",
}
FLOAT_FIELDS = {
    "sdrbrightness", "sdrsaturation", "sdr_min_luminance", "min_luminance",
}
BOOLEAN_FIELDS = {"disabled", "disable"}


def _lua_quote(value: object) -> str:
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _number(value: object) -> str:
    number = float(value)
    if number.is_integer():
        return str(int(number))
    return f"{number:.6g}"


def parse_monitor_line(line: str) -> dict[str, Any]:
    """Parse the scalar fields Cloud Center supports from one hl.monitor call."""
    if not line.strip().startswith("hl.monitor("):
        return {}

    fields: dict[str, Any] = {}
    for key in STRING_FIELDS:
        match = re.search(rf'\b{re.escape(key)}\s*=\s*"((?:\\.|[^"])*)"', line)
        if match:
            fields[key] = bytes(match.group(1), "utf-8").decode("unicode_escape")
    for key in INTEGER_FIELDS:
        match = re.search(rf"\b{re.escape(key)}\s*=\s*(-?\d+)", line)
        if match:
            fields[key] = int(match.group(1))
    for key in FLOAT_FIELDS:
        match = re.search(rf"\b{re.escape(key)}\s*=\s*(-?(?:\d+(?:\.\d*)?|\.\d+))", line)
        if match:
            fields[key] = float(match.group(1))
    for key in BOOLEAN_FIELDS:
        match = re.search(rf"\b{re.escape(key)}\s*=\s*(true|false)", line)
        if match:
            fields["disabled" if key == "disable" else key] = match.group(1) == "true"
    return fields


def logical_size(draft: dict[str, Any]) -> tuple[int, int]:
    """Return Hyprland logical layout dimensions for a staged monitor draft."""
    width = int(draft.get("width", 0) or 0)
    height = int(draft.get("height", 0) or 0)
    match = re.search(r"(?:^|\s)(\d+)x(\d+)@", str(draft.get("mode", "")))
    if match:
        width, height = int(match.group(1)), int(match.group(2))

    transform = int(draft.get("transform", 0) or 0)
    if transform % 2 == 1:
        width, height = height, width

    scale = float(draft.get("scale", 1.0) or 1.0)
    return (
        max(1, int(round(width / scale))),
        max(1, int(round(height / scale))),
    )


def build_monitor_line(draft: dict[str, Any]) -> str:
    """Serialize one frontend draft to a Hyprland 0.55 Lua monitor rule."""
    name = str(draft.get("name", draft.get("output", "")))
    if not bool(draft.get("enabled", not draft.get("disabled", False))):
        return f"hl.monitor({{ output = {_lua_quote(name)}, disabled = true }})"

    mode = re.sub(r"Hz$", "", str(draft.get("mode", "preferred")), flags=re.IGNORECASE)
    x = int(draft.get("x", draft.get("pos_x", 0)) or 0)
    y = int(draft.get("y", draft.get("pos_y", 0)) or 0)
    scale_value = draft.get("scale", 1.0)
    try:
        scale = _number(scale_value)
    except (TypeError, ValueError):
        scale = _lua_quote(scale_value)

    fields = [
        f"output = {_lua_quote(name)}",
        f"mode = {_lua_quote(mode)}",
        f"position = {_lua_quote(f'{x}x{y}')}",
        f"scale = {scale}",
    ]

    transform = int(draft.get("transform", 0) or 0)
    if transform:
        fields.append(f"transform = {transform}")
    mirror = str(draft.get("mirror_of", draft.get("mirror", "")) or "")
    if mirror and mirror.lower() != "none":
        fields.append(f"mirror = {_lua_quote(mirror)}")

    bitdepth = int(draft.get("bitdepth", 8) or 8)
    if bitdepth != 8:
        fields.append(f"bitdepth = {bitdepth}")
    cm = str(draft.get("cm", "srgb") or "srgb")
    if cm != "srgb":
        fields.append(f"cm = {_lua_quote(cm)}")
    sdr_eotf = str(draft.get("sdr_eotf", "default") or "default")
    if sdr_eotf != "default":
        fields.append(f"sdr_eotf = {_lua_quote(sdr_eotf)}")

    for key, default in (("sdrbrightness", 1.0), ("sdrsaturation", 1.0)):
        value = float(draft.get(key, default) or default)
        if value != default:
            fields.append(f"{key} = {_number(value)}")
    vrr = int(draft.get("vrr", 0) or 0)
    if vrr:
        fields.append(f"vrr = {vrr}")
    icc = str(draft.get("icc", "") or "")
    if icc:
        fields.append(f"icc = {_lua_quote(icc)}")

    return f"hl.monitor({{ {', '.join(fields)} }})"


def layout_lines(drafts: Iterable[dict[str, Any]]) -> list[str]:
    """Return monitor rules followed by exclusive workspace assignments."""
    draft_list = list(drafts)
    lines = [build_monitor_line(draft) for draft in draft_list]
    seen_workspaces: set[str] = set()
    for draft in draft_list:
        name = str(draft.get("name", ""))
        for workspace in draft.get("workspaces", []):
            workspace = str(workspace).strip()
            if not workspace or workspace in seen_workspaces:
                continue
            seen_workspaces.add(workspace)
            lines.append(
                "hl.workspace_rule({ workspace = "
                f"{_lua_quote(workspace)}, monitor = {_lua_quote(name)} }})"
            )
    return lines


def _is_managed_layout_line(raw: str) -> bool:
    stripped = raw.strip()
    if stripped.startswith("hl.monitor(") or stripped.startswith("monitor="):
        return True
    if stripped.startswith("hl.workspace_rule("):
        return bool(re.search(r'\bmonitor\s*=\s*"', stripped))
    if stripped.startswith("workspace="):
        return "monitor:" in stripped
    return False


def render_layout_config(original: str, drafts: Iterable[dict[str, Any]]) -> str:
    """Replace managed monitor/workspace rules while preserving other bytes."""
    source = original.splitlines(keepends=True)
    generated = [line + "\n" for line in layout_lines(drafts)]
    out: list[str] = []
    inserted = False
    for raw in source:
        if _is_managed_layout_line(raw):
            if not inserted:
                out.extend(generated)
                inserted = True
            continue
        out.append(raw)

    if not inserted:
        if out and not out[-1].endswith("\n"):
            out[-1] += "\n"
        if out and out[-1].strip():
            out.append("\n")
        out.extend(generated)
    return "".join(out)
