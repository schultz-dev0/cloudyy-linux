"""Merge Hyprland animation leaf specs for Cloud Center → `hcm apply`.

HCM stores `animations:animation` as one or more comma-specs joined by `;`:
`windows,1,4,snap;workspaces,1,4,snap,slidevert`.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

from lib import utility

SENTINEL_RE = re.compile(
    r"^-- @cloud-center-state = (\{.*\})\s*$",
    re.MULTILINE,
)

DEFAULT_BEZIER = "snap"
DEFAULT_WS_STYLE = "slidevert"
KEY_SPEED = "hypr/anim_speed"
KEY_WS_STYLE = "hypr/workspace_anim_style"
# Cloud Center slider: higher = faster. Hyprland's animation speed is a
# duration factor (higher = slower), so we invert on apply: hypr = 11 - ui.
SPEED_MIN = 1
SPEED_MAX = 10
DEFAULT_UI_SPEED = 7  # → Hyprland speed 4 (previous default feel)


def user_animations_path(hypr_dir: Path | None = None) -> Path:
    root = hypr_dir or (Path.home() / ".config" / "hypr")
    return root / "user-configs" / "user_animations.lua"


def load_hcm_animation_state(hypr_dir: Path | None = None) -> dict[str, str]:
    path = user_animations_path(hypr_dir)
    if not path.is_file():
        return {}
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    match = SENTINEL_RE.search(text)
    if not match:
        return {}
    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError:
        return {}
    return {str(k): str(v) for k, v in data.items()}


def parse_specs(value: str) -> list[list[str]]:
    specs: list[list[str]] = []
    for chunk in value.split(";"):
        chunk = chunk.strip()
        if not chunk:
            continue
        parts = [p.strip() for p in chunk.split(",")]
        if len(parts) >= 4:
            specs.append(parts)
    return specs


def serialize_specs(specs: list[list[str]]) -> str:
    return ";".join(",".join(parts) for parts in specs if len(parts) >= 4)


def current_specs(hypr_dir: Path | None = None) -> list[list[str]]:
    state = load_hcm_animation_state(hypr_dir)
    return parse_specs(state.get("animations:animation", ""))


def bezier_name(hypr_dir: Path | None = None) -> str:
    state = load_hcm_animation_state(hypr_dir)
    raw = state.get("animations:bezier", "")
    if raw:
        name = raw.split(",", 1)[0].strip()
        if name:
            return name
    for parts in current_specs(hypr_dir):
        if parts[0] == "windows" and parts[3]:
            return parts[3]
    return DEFAULT_BEZIER


def clamp_ui_speed(value: int | float) -> int:
    return max(SPEED_MIN, min(SPEED_MAX, int(float(value))))


def ui_to_hypr_speed(ui_speed: int | float) -> int:
    """Map Cloud Center slider (higher=faster) → Hyprland duration (higher=slower)."""
    return SPEED_MAX + SPEED_MIN - clamp_ui_speed(ui_speed)


def hypr_speed_from_setting(default_ui: int = DEFAULT_UI_SPEED) -> int:
    try:
        ui = clamp_ui_speed(utility.load_setting(KEY_SPEED, default_ui))
    except Exception:
        ui = DEFAULT_UI_SPEED
    return ui_to_hypr_speed(ui)


def anim_speed() -> int:
    """Hyprland-native speed to write into animation leaf specs."""
    return hypr_speed_from_setting()


def workspace_style() -> str:
    style = str(utility.load_setting(KEY_WS_STYLE, DEFAULT_WS_STYLE) or DEFAULT_WS_STYLE).strip()
    return style or DEFAULT_WS_STYLE


def upsert_leaf(
    specs: list[list[str]],
    leaf: str,
    *,
    enabled: bool | None = None,
    speed: int | None = None,
    bezier: str | None = None,
    style: str | None = None,
) -> list[list[str]]:
    out = [list(p) for p in specs]
    for parts in out:
        if parts[0] != leaf:
            continue
        if enabled is not None:
            parts[1] = "1" if enabled else "0"
        if speed is not None:
            parts[2] = str(int(speed))
        if bezier is not None:
            parts[3] = bezier
        if style is not None:
            if len(parts) > 4:
                parts[4:] = [style]
            else:
                parts.append(style)
        return out

    # New leaf — seed from windows when possible.
    win = next((p for p in out if p[0] == "windows"), None)
    en = "1" if (True if enabled is None else enabled) else "0"
    spd = str(int(speed if speed is not None else (int(win[2]) if win else anim_speed())))
    bez = bezier or (win[3] if win else bezier_name())
    parts = [leaf, en, spd, bez]
    if style or leaf == "workspaces":
        parts.append(style or workspace_style())
    out.append(parts)
    return out


def hcm_apply_animation(value: str, *, hypr_dir: Path | None = None) -> dict[str, Any]:
    cmd = ["hcm", "apply", "animations:animation", value]
    if hypr_dir is not None:
        cmd = ["hcm", "--hypr-dir", str(hypr_dir), "apply", "animations:animation", value]
    try:
        run = subprocess.run(cmd, capture_output=True, text=True, timeout=8)
    except Exception as exc:
        return {"ok": False, "message": f"Apply failed: {exc}"}
    if run.returncode != 0:
        err = (run.stderr or run.stdout or "hcm apply failed").strip()
        return {"ok": False, "message": f"Apply failed: {err}"}
    return {"ok": True, "message": f"persisted animations:animation = {value}", "value": value}


def apply_speed(ui_speed: int, *, hypr_dir: Path | None = None) -> dict[str, Any]:
    ui = clamp_ui_speed(ui_speed)
    utility.save_setting(KEY_SPEED, ui)
    hypr = ui_to_hypr_speed(ui)
    specs = current_specs(hypr_dir)
    if not specs:
        specs = [["windows", "1", str(hypr), bezier_name(hypr_dir)]]
    else:
        for parts in specs:
            parts[2] = str(hypr)
    return hcm_apply_animation(serialize_specs(specs), hypr_dir=hypr_dir)


def apply_workspace_enabled(enabled: bool, *, hypr_dir: Path | None = None) -> dict[str, Any]:
    specs = upsert_leaf(
        current_specs(hypr_dir),
        "workspaces",
        enabled=enabled,
        speed=anim_speed(),
        bezier=bezier_name(hypr_dir),
        style=workspace_style(),
    )
    # Ensure windows exists so Bezier/speed edits keep a primary leaf.
    if not any(p[0] == "windows" for p in specs):
        specs.insert(0, ["windows", "1", str(anim_speed()), bezier_name(hypr_dir)])
    return hcm_apply_animation(serialize_specs(specs), hypr_dir=hypr_dir)


def apply_workspace_style(style: str, *, hypr_dir: Path | None = None) -> dict[str, Any]:
    cleaned = str(style or "").strip() or DEFAULT_WS_STYLE
    utility.save_setting(KEY_WS_STYLE, cleaned)
    specs = current_specs(hypr_dir)
    enabled = True
    for parts in specs:
        if parts[0] == "workspaces":
            enabled = parts[1] in ("1", "true")
            break
    specs = upsert_leaf(
        specs,
        "workspaces",
        enabled=enabled,
        speed=anim_speed(),
        bezier=bezier_name(hypr_dir),
        style=cleaned,
    )
    if not any(p[0] == "windows" for p in specs):
        specs.insert(0, ["windows", "1", str(anim_speed()), bezier_name(hypr_dir)])
    return hcm_apply_animation(serialize_specs(specs), hypr_dir=hypr_dir)


def upsert_windows_leaf(
    *,
    speed: int | None = None,
    bezier: str | None = None,
    hypr_dir: Path | None = None,
) -> str:
    """Return merged animation value with windows leaf updated (preserves others)."""
    specs = upsert_leaf(
        current_specs(hypr_dir),
        "windows",
        enabled=True,
        speed=speed if speed is not None else anim_speed(),
        bezier=bezier or bezier_name(hypr_dir),
    )
    return serialize_specs(specs)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="hypr_anim")
    parser.add_argument("--hypr-dir", type=Path, default=None)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_speed = sub.add_parser("speed")
    p_speed.add_argument("value", type=int)

    p_ws = sub.add_parser("workspace-enabled")
    p_ws.add_argument("value", choices=("true", "false", "1", "0"))

    p_style = sub.add_parser("workspace-style")
    p_style.add_argument("value")

    args = parser.parse_args(argv)
    hypr_dir = args.hypr_dir

    if args.cmd == "speed":
        result = apply_speed(args.value, hypr_dir=hypr_dir)
    elif args.cmd == "workspace-enabled":
        result = apply_workspace_enabled(
            args.value in ("true", "1"), hypr_dir=hypr_dir
        )
    else:
        result = apply_workspace_style(args.value, hypr_dir=hypr_dir)

    print(json.dumps(result))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
