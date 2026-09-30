"""
Cloud Center — lib/keyboard_device_persist.py
Enables/disables the laptop's built-in keyboard via Hyprland's per-device
config (`hl.device({...})`). Independent of the global input:* settings
owned by hypr_layout_persist.py — device blocks are a different Hyprland
config surface (per-device, not nested under `input`) — so this owns its
own managed block inside the same input.lua file rather than extending
hypr_layout_persist's LAYOUT table.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

from lib import hcm_lua

# atkbd's synthetic libinput name for the AT/PS2-emulated internal keyboard
# controller present on virtually every x86 laptop — the standard, portable
# way to target "the built-in keyboard" regardless of make/model.
DEVICE_NAME = "at-translated-set-2-keyboard"

_BEGIN = "-- --- Cloud Center managed keyboard device settings ---"
_END = "-- --- End Cloud Center managed keyboard device settings ---"


def _input_lua_path():
    # Resolved fresh each call (not a frozen module-level constant) — same
    # reasoning as hypr_layout_persist._surface_path: lets tests
    # mock.patch.object(hcm_lua, "HYPR_DIR", ...).
    return hcm_lua.HYPR_DIR / "input.lua"


def _render(enabled: bool) -> list[str]:
    if enabled:
        return []  # nothing to override; the device defaults to enabled
    return [
        "hl.device({",
        f"    name = {json.dumps(DEVICE_NAME)},",
        "    enabled = false,",
        "})",
    ]


def _persist(enabled: bool) -> None:
    """Rewrite input.lua's managed keyboard-device block in place, leaving
    everything else (including hypr_layout_persist's own managed block and
    sentinel line) untouched — mirrors hypr_layout_persist._persist's
    file-rewrite shape."""
    path = _input_lua_path()
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    lines = text.splitlines()

    block = _render(enabled)
    out_lines: list[str] = []
    i = 0
    found = False
    while i < len(lines):
        if lines[i] == _BEGIN:
            found = True
            out_lines.append(_BEGIN)
            out_lines.extend(block)
            out_lines.append(_END)
            i += 1
            while i < len(lines) and lines[i] != _END:
                i += 1
            i += 1  # skip end marker
            continue
        out_lines.append(lines[i])
        i += 1
    if not found:
        out_lines.append(_BEGIN)
        out_lines.extend(block)
        out_lines.append(_END)

    hcm_lua.atomic_write(path, "\n".join(out_lines).rstrip("\n") + "\n")


def _hyprctl_eval_ok(expr: str) -> bool:
    try:
        out = subprocess.run(["hyprctl", "eval", expr], capture_output=True, text=True, timeout=5)
    except (subprocess.SubprocessError, OSError):
        return False
    combined = out.stdout + out.stderr
    return "error:" not in combined and "attempt to call a nil value" not in combined


def _apply_live(enabled: bool) -> None:
    expr = f'hl.device({{ name = {json.dumps(DEVICE_NAME)}, enabled = {"true" if enabled else "false"} }})'
    if not _hyprctl_eval_ok(expr):
        subprocess.run(["hyprctl", "reload"], capture_output=True)


def set_keyboard_enabled(enabled: bool) -> bool:
    _persist(enabled)
    _apply_live(enabled)
    return enabled


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="keyboard_device_persist")
    parser.add_argument("state", choices=["on", "off"])
    args = parser.parse_args(argv)

    try:
        payload = {"ok": True, "enabled": set_keyboard_enabled(args.state == "on")}
    except Exception as exc:
        print(json.dumps({"ok": False, "message": str(exc)}))
        return 1

    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())
