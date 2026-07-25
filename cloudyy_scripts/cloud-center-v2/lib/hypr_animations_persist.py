"""
Cloud Center — lib/hypr_animations_persist.py
Persists animations:bezier / animations:animation into the single
~/.config/hypr/animations.lua, in place. Python port of the animations
subset of ~/projects/hcm/src/persist.rs — the only hcm schema surface any
current UI page actually writes to (see the plan's "Corrections" section).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

from lib import hcm_lua

MANAGED_BEGIN = "-- --- Cloud Center managed animation settings ---"
MANAGED_END = "-- --- End Cloud Center managed animation settings ---"
SENTINEL_PREFIX = "-- @cloud-center-state = "


def _animations_lua_path():
    # ponytail: read hcm_lua.HYPR_DIR fresh each call (not a frozen module
    # constant) so tests can mock.patch.object(hcm_lua, "HYPR_DIR", ...).
    return hcm_lua.HYPR_DIR / "animations.lua"


def _is_numeric(s: str) -> bool:
    body = s[1:] if s.startswith("-") else s
    return bool(body) and body != "." and body.count(".") <= 1 and all(c.isdigit() or c == "." for c in body)


def _lua_value(v: str) -> str:
    if v in ("true", "false"):
        return v
    if _is_numeric(v):
        return v
    return json.dumps(v)


def render_curve(value: str) -> str | None:
    """Parse `name,x1,y1,x2,y2` into an `hl.curve(...)` call."""
    parts = [p.strip() for p in value.split(",")]
    if len(parts) != 5:
        return None
    name, x1, y1, x2, y2 = parts
    return f'hl.curve({_lua_value(name)}, {{ type = "bezier", points = {{ {{ {x1}, {y1} }}, {{ {x2}, {y2} }} }} }})'


def render_animation(value: str) -> str | None:
    """Parse `leaf,enabled,speed[,bezier[,style…]]` into an `hl.animation(...)` call.

    Rust's render_animation requires >=4 parts (leaf,enabled,speed,bezier).
    Real seeded state also has disabled leaves with no bezier at all, e.g.
    `layersOut,0,0` -> `hl.animation({ leaf = "layersOut", enabled = false,
    speed = 0 })` (see install/default-theme/hypr/animations.lua) — so the
    bezier/style fields are conditional on their parts being present, and the
    hard minimum is leaf,enabled,speed (3 parts).
    """
    parts = [p.strip() for p in value.split(",")]
    if len(parts) < 3:
        return None
    leaf, enabled, speed = parts[:3]
    enabled_lua = "true" if enabled in ("1", "true") else "false"
    fields = [
        f"leaf = {_lua_value(leaf)}",
        f"enabled = {enabled_lua}",
        f"speed = {_lua_value(speed)}",
    ]
    if len(parts) >= 4:
        fields.append(f"bezier = {_lua_value(parts[3])}")
    if len(parts) > 4:
        fields.append(f"style = {_lua_value(','.join(parts[4:]))}")
    return f"hl.animation({{ {', '.join(fields)} }})"


def animation_specs(value: str) -> list[str]:
    """`animations:animation` may hold one spec or several joined with `;`."""
    return [s.strip() for s in value.split(";") if s.strip()]


def _render_managed_lines(state: dict[str, str]) -> list[str]:
    lines = []
    if "animations:enabled" in state:
        lines.append(f"hl.config({{ animations = {{ enabled = {_lua_value(state['animations:enabled'])} }} }})")
    if "animations:bezier" in state:
        line = render_curve(state["animations:bezier"])
        if line:
            lines.append(line)
    if "animations:animation" in state:
        for spec in animation_specs(state["animations:animation"]):
            line = render_animation(spec)
            if line:
                lines.append(line)
    return lines


def build_live_evals(key: str, value: str) -> list[str]:
    """Build `hyprctl eval` expression(s) for a managed animation key."""
    if key == "animations:bezier":
        line = render_curve(value)
        return [line] if line else []
    if key == "animations:animation":
        return [render_animation(spec) for spec in animation_specs(value) if render_animation(spec)]
    return []


def _hyprctl_eval_ok(expr: str) -> bool:
    try:
        out = subprocess.run(["hyprctl", "eval", expr], capture_output=True, text=True, timeout=5)
    except (subprocess.SubprocessError, OSError):
        return False
    combined = out.stdout + out.stderr
    return "error:" not in combined and "keyword can't work" not in combined and "attempt to call a nil value" not in combined


def _reload_hyprland() -> None:
    subprocess.run(["hyprctl", "reload"], capture_output=True)


def _read_state(path) -> dict[str, str]:
    if not path.exists():
        return {}
    for line in path.read_text(encoding="utf-8").splitlines()[:3]:
        if line.startswith(SENTINEL_PREFIX):
            try:
                return json.loads(line[len(SENTINEL_PREFIX):])
            except json.JSONDecodeError:
                return {}
    return {}


def _persist_state(path, state: dict[str, str]) -> None:
    """Rewrite animations.lua's sentinel line and managed block in place,
    leaving everything else in the file untouched."""
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    lines = text.splitlines()

    new_sentinel = f"{SENTINEL_PREFIX}{json.dumps(state, sort_keys=True)}"
    if lines and lines[0].startswith(SENTINEL_PREFIX):
        lines[0] = new_sentinel
    else:
        lines.insert(0, new_sentinel)

    managed_lines = _render_managed_lines(state)
    out_lines: list[str] = []
    i = 0
    found = False
    while i < len(lines):
        if lines[i] == MANAGED_BEGIN:
            found = True
            out_lines.append(MANAGED_BEGIN)
            out_lines.extend(managed_lines)
            out_lines.append(MANAGED_END)
            i += 1
            while i < len(lines) and lines[i] != MANAGED_END:
                i += 1
            i += 1  # skip MANAGED_END
            continue
        out_lines.append(lines[i])
        i += 1
    if not found:
        out_lines.append(MANAGED_BEGIN)
        out_lines.extend(managed_lines)
        out_lines.append(MANAGED_END)

    hcm_lua.atomic_write(path, "\n".join(out_lines).rstrip("\n") + "\n")


def apply_animation_key(key: str, value: str) -> None:
    """Persist key=value into animations.lua's managed block, then live-apply.

    Mirrors ~/projects/hcm/src/persist.rs `apply()`: persist first, then run
    the equivalent `hyprctl eval` expression(s), falling back to a full
    `hyprctl reload` if any eval fails.
    """
    path = _animations_lua_path()
    state = _read_state(path)
    state[key] = value
    _persist_state(path, state)

    exprs = build_live_evals(key, value)
    if exprs and not all(_hyprctl_eval_ok(e) for e in exprs):
        _reload_hyprland()


def clear_key(key: str) -> None:
    """Remove `key` from animations.lua's managed state (no-op if absent).

    Used by hypr_layout_persist.reset_page("hyprland") to also clear
    animations:enabled alongside the general/decoration keys it owns —
    persist.rs's PAGE_HYPRLAND spans both lookandfeel.lua and animations.lua.
    Persist-only, no live hyprctl eval/reload — matches persist.rs's
    reset_page, which doesn't live-apply either.

    Note: this is the surgical "reset" — it clears state for one key, leaving
    an EMPTY managed block that falls back to the static distro body. That's
    a different, finer-grained operation than hcm_lua.reset_to_default(),
    which whole-file-replaces animations.lua (and lookandfeel/input) from the
    shipped seed — and for those three modules that seed contains a POPULATED
    managed block (real personal defaults), not an empty one. See
    hcm_lua.reset_to_default's docstring for the contrast; be intentional
    about which "reset" a given UI action should invoke.
    """
    path = _animations_lua_path()
    state = _read_state(path)
    if key not in state:
        return
    del state[key]
    _persist_state(path, state)


def main(argv: list[str] | None = None) -> int:
    """`python3 -m lib.hypr_animations_persist apply <key> <value>` — the
    generic entry point config.yaml uses for the Hyprland page's master
    "Animations" toggle (`animations:enabled`), which isn't one of the
    higher-level hypr_anim.py commands (speed/workspace-enabled/
    workspace-style)."""
    parser = argparse.ArgumentParser(prog="hypr_animations_persist")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_apply = sub.add_parser("apply")
    p_apply.add_argument("key")
    p_apply.add_argument("value")

    args = parser.parse_args(argv)

    try:
        apply_animation_key(args.key, args.value)
    except Exception as exc:
        print(json.dumps({"ok": False, "message": str(exc)}))
        return 1

    print(json.dumps({"ok": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
