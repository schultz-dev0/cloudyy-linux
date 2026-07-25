"""
Cloud Center — lib/hypr_layout_persist.py
Persists the `general:*` / `decoration:*` (lookandfeel.lua) and `input:*`
(input.lua) settings that drive the Input and Hyprland/lookandfeel UI pages.
Python port of the non-animations, non-cursor subset of
~/projects/hcm/src/persist.rs's LAYOUT/render_table/apply/reset_page —
`cursor:*` stays owned by `ccd/cursor.py` and `animations:*` stays owned by
`hypr_animations_persist.py`.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

from lib import hcm_lua

SENTINEL_PREFIX = "-- @cloud-center-state = "

MANAGED_MARKERS = {
    "lookandfeel": (
        "-- --- Cloud Center managed lookandfeel settings ---",
        "-- --- End Cloud Center managed lookandfeel settings ---",
    ),
    "input": (
        "-- --- Cloud Center managed input settings ---",
        "-- --- End Cloud Center managed input settings ---",
    ),
}

# key -> (section, subsection, config_key). Declaration order matters: render
# passes iterate in this order to produce stable output — mirrors persist.rs's
# LAYOUT (minus its cursor:* and animations:* entries, owned elsewhere).
LAYOUT: list[tuple[str, str, str | None, str]] = [
    ("general:border_size", "general", None, "border_size"),
    ("general:gaps_out", "general", None, "gaps_out"),
    ("general:gaps_in", "general", None, "gaps_in"),
    ("general:layout", "general", None, "layout"),
    ("decoration:rounding", "decoration", None, "rounding"),
    ("decoration:active_opacity", "decoration", None, "active_opacity"),
    ("decoration:inactive_opacity", "decoration", None, "inactive_opacity"),
    ("decoration:shadow:enabled", "decoration", "shadow", "enabled"),
    ("decoration:shadow:range", "decoration", "shadow", "range"),
    ("decoration:shadow:render_power", "decoration", "shadow", "render_power"),
    ("decoration:blur:enabled", "decoration", "blur", "enabled"),
    ("decoration:blur:passes", "decoration", "blur", "passes"),
    ("decoration:blur:size", "decoration", "blur", "size"),
    ("input:kb_layout", "input", None, "kb_layout"),
    ("input:kb_variant", "input", None, "kb_variant"),
    ("input:kb_model", "input", None, "kb_model"),
    ("input:kb_options", "input", None, "kb_options"),
    ("input:kb_rules", "input", None, "kb_rules"),
    ("input:repeat_delay", "input", None, "repeat_delay"),
    ("input:repeat_rate", "input", None, "repeat_rate"),
    ("input:follow_mouse", "input", None, "follow_mouse"),
    ("input:sensitivity", "input", None, "sensitivity"),
    ("input:accel_profile", "input", None, "accel_profile"),
    ("input:natural_scroll", "input", None, "natural_scroll"),
    ("input:numlock_by_default", "input", None, "numlock_by_default"),
    ("input:touchpad:natural_scroll", "input", "touchpad", "natural_scroll"),
    ("input:touchpad:disable_while_typing", "input", "touchpad", "disable_while_typing"),
    ("input:touchpad:clickfinger_behavior", "input", "touchpad", "clickfinger_behavior"),
    ("input:touchpad:middle_button_emulation", "input", "touchpad", "middle_button_emulation"),
    ("input:touchpad:scroll_factor", "input", "touchpad", "scroll_factor"),
]

_LOOKUP = {key: (section, sub, config_key) for key, section, sub, config_key in LAYOUT}

SURFACE_OF = {
    key: ("lookandfeel" if section in ("general", "decoration") else "input")
    for key, section, _sub, _config_key in LAYOUT
}

SECTIONS_OF = {"lookandfeel": ("general", "decoration"), "input": ("input",)}

# What `reset-page hyprland` / `reset-page input` clear. Mirrors persist.rs's
# PAGE_HYPRLAND (minus its animations:* entries — those are cleared via
# hypr_animations_persist.clear_key, since they live in animations.lua) and
# PAGE_INPUT.
PAGE_HYPRLAND = [key for key, section, _sub, _ck in LAYOUT if section in ("general", "decoration")]
PAGE_INPUT = [key for key, section, _sub, _ck in LAYOUT if section == "input"]


def _surface_path(surface: str):
    # ponytail: resolve hcm_lua.HYPR_DIR fresh each call (not a frozen
    # constant), same reasoning as hypr_animations_persist._animations_lua_path
    # — lets tests mock.patch.object(hcm_lua, "HYPR_DIR", ...).
    return hcm_lua.HYPR_DIR / f"{surface}.lua"


def _is_numeric(s: str) -> bool:
    body = s[1:] if s.startswith("-") else s
    return bool(body) and body != "." and body.count(".") <= 1 and all(c.isdigit() or c == "." for c in body)


def _lua_value(v: str) -> str:
    if v in ("true", "false"):
        return v
    if _is_numeric(v):
        return v
    return json.dumps(v)


def _lua_key(k: str) -> str:
    """Bare identifiers stay bare; everything else becomes `["…"]`."""
    if k and (k[0].isalpha() or k[0] == "_") and all(c.isalnum() or c == "_" for c in k):
        return k
    return f"[{json.dumps(k)}]"


def render_table(state: dict[str, str], surface: str) -> list[str]:
    """Render the `hl.config({...})` table for a surface, generically handling
    the `shadow`/`blur`/`touchpad` subsections (not per-key) — port of
    persist.rs's render_table."""
    sections = SECTIONS_OF.get(surface, ())
    if not sections:
        return []

    def pick(section: str) -> list[tuple[str | None, str, str]]:
        return [
            (sub, config_key, state[key])
            for key, sec, sub, config_key in LAYOUT
            if sec == section and SURFACE_OF.get(key) == surface and key in state
        ]

    picks = {section: pick(section) for section in sections}
    if all(not entries for entries in picks.values()):
        return []

    lines = ["hl.config({"]
    for section in sections:
        entries = picks[section]
        if not entries:
            continue
        lines.append(f"    {section} = {{")

        for sub, config_key, value in entries:
            if sub is None:
                lines.append(f"        {_lua_key(config_key)} = {_lua_value(value)},")

        subs: list[str] = []
        for sub, _config_key, _value in entries:
            if sub is not None and sub not in subs:
                subs.append(sub)
        for sub in subs:
            lines.append(f"        {sub} = {{")
            for s2, config_key, value in entries:
                if s2 == sub:
                    lines.append(f"            {_lua_key(config_key)} = {_lua_value(value)},")
            lines.append("        },")

        lines.append("    },")
    lines.append("})")
    return lines


def build_live_eval(key: str, value: str) -> str | None:
    """Build a single `hyprctl eval` expression for a managed key — port of
    persist.rs's build_live_eval (the layout subset has no multi-expr keys,
    unlike animations:animation)."""
    entry = _LOOKUP.get(key)
    if entry is None:
        return None
    section, sub, config_key = entry
    v = _lua_value(value)
    ck = _lua_key(config_key.replace("-", "_"))
    if sub:
        return f"hl.config({{ {section} = {{ {sub} = {{ {ck} = {v} }} }} }})"
    return f"hl.config({{ {section} = {{ {ck} = {v} }} }})"


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


def _persist(surface: str, state: dict[str, str]) -> None:
    """Rewrite `surface.lua`'s sentinel line and managed block in place,
    leaving everything else in the file untouched. Mirrors
    hypr_animations_persist.apply_animation_key's file-rewrite shape."""
    path = _surface_path(surface)
    begin, end = MANAGED_MARKERS[surface]

    text = path.read_text(encoding="utf-8") if path.exists() else ""
    lines = text.splitlines()

    new_sentinel = f"{SENTINEL_PREFIX}{json.dumps(state, sort_keys=True)}"
    if lines and lines[0].startswith(SENTINEL_PREFIX):
        lines[0] = new_sentinel
    else:
        lines.insert(0, new_sentinel)

    managed_lines = render_table(state, surface)
    out_lines: list[str] = []
    i = 0
    found = False
    while i < len(lines):
        if lines[i] == begin:
            found = True
            out_lines.append(begin)
            out_lines.extend(managed_lines)
            out_lines.append(end)
            i += 1
            while i < len(lines) and lines[i] != end:
                i += 1
            i += 1  # skip end marker
            continue
        out_lines.append(lines[i])
        i += 1
    if not found:
        out_lines.append(begin)
        out_lines.extend(managed_lines)
        out_lines.append(end)

    hcm_lua.atomic_write(path, "\n".join(out_lines).rstrip("\n") + "\n")


def apply(key: str, value: str) -> None:
    """Persist a key, then apply it live via `hyprctl eval` (reload on eval
    failure) — port of persist.rs's apply()/set()."""
    surface = SURFACE_OF.get(key)
    if surface is None:
        print(f"[hypr_layout_persist] WARNING: unsupported key '{key}', skipping", file=sys.stderr)
        return

    path = _surface_path(surface)
    state = _read_state(path)
    state[key] = value
    _persist(surface, state)

    expr = build_live_eval(key, value)
    if expr is not None and not _hyprctl_eval_ok(expr):
        _reload_hyprland()


def reset_page(name: str) -> None:
    """Clear every key on a page — port of persist.rs's reset_page(). Unlike
    `apply`, this only persists (no live hyprctl eval/reload), matching
    persist.rs's actual reset_page, which does the same.

    Note: this is the surgical "reset" — it clears per-key state, leaving an
    EMPTY managed block that falls back to the static distro body (e.g.
    border_size = 0). That's a different, finer-grained operation than
    hcm_lua.reset_to_default(), which whole-file-replaces lookandfeel/input/
    animations from the shipped seed — and for those three modules that seed
    contains a POPULATED managed block (real personal defaults, e.g.
    border_size = 1), not an empty one. See hcm_lua.reset_to_default's
    docstring for the contrast; be intentional about which "reset" a given UI
    action should invoke."""
    if name == "hyprland":
        path = _surface_path("lookandfeel")
        state = _read_state(path)
        for key in PAGE_HYPRLAND:
            state.pop(key, None)
        _persist("lookandfeel", state)

        from lib import hypr_animations_persist

        # persist.rs's PAGE_HYPRLAND (lines 123-129) clears all three
        # animations:* keys, not just animations:enabled — they live in
        # animations.lua, not lookandfeel.lua, hence the separate clear_key
        # calls instead of folding them into this module's own state dict.
        for key in ("animations:enabled", "animations:bezier", "animations:animation"):
            hypr_animations_persist.clear_key(key)
    elif name == "input":
        path = _surface_path("input")
        state = _read_state(path)
        for key in PAGE_INPUT:
            state.pop(key, None)
        _persist("input", state)
    else:
        raise ValueError(f"unknown page '{name}'")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="hypr_layout_persist")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_apply = sub.add_parser("apply")
    p_apply.add_argument("key")
    p_apply.add_argument("value")

    p_reset = sub.add_parser("reset-page")
    p_reset.add_argument("page")

    args = parser.parse_args(argv)

    try:
        if args.cmd == "apply":
            apply(args.key, args.value)
        else:
            reset_page(args.page)
    except Exception as exc:
        print(json.dumps({"ok": False, "message": str(exc)}))
        return 1

    print(json.dumps({"ok": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
