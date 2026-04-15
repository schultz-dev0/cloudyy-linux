"""
waybar-editor/writer.py
Write edited preset data back to config.jsonc and style.css atomically.
"""
from __future__ import annotations

import contextlib
import json
import logging
import os
import re
import tempfile
from pathlib import Path

from models import CSSVar, Preset, WaybarModule
from parser import strip_jsonc

log = logging.getLogger(__name__)


def _atomic_write(path: Path, text: str) -> None:
    fd, tmp_str = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        Path(tmp_str).rename(path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp_str)
        raise


# ── CSS writer ────────────────────────────────────────────────────────────────

def update_css_var(css: str, var: CSSVar) -> str:
    """Replace a @define-color line with the updated value."""
    pattern = re.compile(
        r"(@define-color\s+" + re.escape(var.name) + r"\s+)([^;]+)(;)"
    )
    def replacer(m):
        return f"{m.group(1)}{var.value}{m.group(3)}"
    new, count = pattern.subn(replacer, css)
    if count == 0:
        # Variable not yet present — append before first non-comment line
        new = f"@define-color {var.name} {var.value};\n" + css
    return new


def update_css_property(css: str, selector: str, prop: str, value: str) -> str:
    """
    Update a property value inside a selector block.
    Handles the first occurrence of the selector only.
    """
    # Find the selector block
    escaped = re.escape(selector)
    block_re = re.compile(
        r"(" + escaped + r"\s*\{)([^}]*)(\})",
        re.DOTALL,
    )
    m = block_re.search(css)
    if not m:
        return css

    block_content = m.group(2)
    prop_re = re.compile(
        r"((?<!\w)(?<!-)" + re.escape(prop) + r"\s*:\s*)([^;]+)(;)"
    )
    new_block, count = prop_re.subn(
        lambda pm: f"{pm.group(1)}{value}{pm.group(3)}",
        block_content,
    )
    if count == 0:
        new_block = block_content.rstrip() + f"\n    {prop}: {value};\n"

    return css[:m.start(2)] + new_block + css[m.end(2):]


def save_css(preset: Preset) -> None:
    """Write the current css_raw (which has been updated in-memory) back to disk."""
    _atomic_write(preset.style_path, preset.css_raw)


# ── Config writer ─────────────────────────────────────────────────────────────

def _module_names(modules: list[WaybarModule]) -> list:
    result = []
    for m in modules:
        if not m.enabled:
            continue
        if m.config:
            result.append({m.name: m.config})
        else:
            result.append(m.name)
    return result


def build_config_str(preset: Preset) -> str:
    """
    Return the config.jsonc content as a JSON string, merging current in-memory
    module lists into whatever other keys are stored in config_raw.
    """
    try:
        cfg = json.loads(strip_jsonc(preset.config_raw))
    except Exception:
        cfg = {}

    cfg["modules-left"]   = _module_names(preset.modules_left)
    cfg["modules-center"] = _module_names(preset.modules_center)
    cfg["modules-right"]  = _module_names(preset.modules_right)

    return json.dumps(cfg, indent=4)


def save_config(preset: Preset) -> None:
    """
    Rewrite modules-left/center/right in config.jsonc preserving all other keys.
    Comments are stripped (unavoidable with JSON round-trip) but all settings kept.
    """
    _atomic_write(preset.config_path, build_config_str(preset))
