"""
waybar-editor/parser.py
Parse waybar config.jsonc and style.css into editor models.
"""
from __future__ import annotations

import json
import logging
import re
from pathlib import Path

log = logging.getLogger(__name__)

from models import (
    CSSProperty, CSSVar, Position, Preset, WaybarModule,
    PRESETS_DIR,
)

# ── JSONC stripper ────────────────────────────────────────────────────────────

def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments from JSONC, preserving strings."""
    # Block comments first
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    # Line comments — skip inside strings
    result = []
    in_string = False
    i = 0
    while i < len(text):
        c = text[i]
        if c == '"' and (i == 0 or text[i - 1] != "\\"):
            in_string = not in_string
        if not in_string and c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        result.append(c)
        i += 1
    return "".join(result)


# ── CSS parser ────────────────────────────────────────────────────────────────

_DEFINE_COLOR = re.compile(
    r"@define-color\s+(\w+)\s+(.+?)\s*;"
)

_IMPORT_URL = re.compile(r'@import\s+url\(["\']?([^"\')\s]+)["\']?\)\s*;')


def collect_css_vars(css: str, style_path: Path | None = None) -> dict[str, str]:
    """
    Return every @define-color variable visible to this CSS, including those
    from @import'd files.  Resolves import paths relative to style_path first;
    falls back to a home-relative lookup for the common `../../.config/…` pattern.
    """
    vars_: dict[str, str] = {}

    if style_path is not None:
        for m in _IMPORT_URL.finditer(css):
            raw = m.group(1)
            candidate = (style_path.parent / raw).resolve()
            if not candidate.exists() and ".config/" in raw:
                # Common pattern: ../../.config/… — resolve from HOME instead
                candidate = (Path.home() / raw[raw.find(".config/"):]).resolve()
            if candidate.exists():
                try:
                    for vm in _DEFINE_COLOR.finditer(candidate.read_text(encoding="utf-8")):
                        vars_[vm.group(1)] = vm.group(2).strip()
                except OSError as e:
                    log.debug("Could not load @import %s: %s", raw, e)
            else:
                log.debug("@import not found: %s", raw)

    # Main file overrides anything imported
    for m in _DEFINE_COLOR.finditer(css):
        vars_[m.group(1)] = m.group(2).strip()

    return vars_

# Properties we expose as structured editors (selector → property)
KNOWN_PROPS = {
    "#waybar":    ["background", "background-color", "color", "font-family",
                   "font-size", "border-radius", "padding"],
    "#clock":     ["padding", "color", "background-color", "border-radius"],
    "#workspaces button":
                  ["padding", "color", "background-color", "border-radius"],
    "#pulseaudio": ["padding", "color", "background-color"],
    "#network":   ["padding", "color"],
    "#battery":   ["padding", "color"],
    "window#waybar": ["background-color", "border-radius"],
    "tooltip":    ["background", "border", "border-radius", "color"],
}

_PROP_VALUE = re.compile(r"([\w-]+)\s*:\s*([^;]+);")


def parse_css(text: str) -> tuple[list[CSSVar], list[CSSProperty]]:
    """Extract @define-color vars and known selector properties."""
    vars_: list[CSSVar] = []
    props: list[CSSProperty] = []

    for i, line in enumerate(text.splitlines()):
        m = _DEFINE_COLOR.search(line)
        if m:
            vars_.append(CSSVar(name=m.group(1), value=m.group(2).strip(), line=i))

    # Extract blocks for known selectors
    # Simple single-level block extraction
    block_re = re.compile(r"([^{]+)\{([^}]*)\}", re.DOTALL)
    for m in block_re.finditer(text):
        selector = m.group(1).strip().rstrip(",").strip()
        block    = m.group(2)
        if selector not in KNOWN_PROPS:
            continue
        allowed = KNOWN_PROPS[selector]
        for pm in _PROP_VALUE.finditer(block):
            prop = pm.group(1).strip()
            val  = pm.group(2).strip()
            if prop in allowed:
                props.append(CSSProperty(selector=selector, prop=prop, value=val))

    return vars_, props


# ── Config parser ─────────────────────────────────────────────────────────────

def parse_config(text: str) -> tuple[list, list, list]:
    """Return (modules_left, modules_center, modules_right) as WaybarModule lists."""
    try:
        cfg = json.loads(strip_jsonc(text))
    except json.JSONDecodeError as e:
        log.warning("Failed to parse config JSON: %s", e)
        return [], [], []

    def make_modules(names, position):
        result = []
        for entry in names:
            if isinstance(entry, str):
                result.append(WaybarModule(name=entry, position=position))
            elif isinstance(entry, dict):
                # Module defined inline as object — use its key if possible
                for k, v in entry.items():
                    if isinstance(v, dict):
                        m = WaybarModule(name=k, position=position, config=v)
                        result.append(m)
                        break
        return result

    left   = make_modules(cfg.get("modules-left",   []), Position.LEFT)
    center = make_modules(cfg.get("modules-center", []), Position.CENTER)
    right  = make_modules(cfg.get("modules-right",  []), Position.RIGHT)
    return left, center, right


# ── Preset loader ─────────────────────────────────────────────────────────────

def load_preset(name: str) -> Preset | None:
    path = PRESETS_DIR / name
    config_path = path / "config.jsonc"
    style_path  = path / "style.css"

    if not path.exists():
        return None

    config_raw = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    css_raw    = style_path.read_text(encoding="utf-8")  if style_path.exists()  else ""

    left, center, right = parse_config(config_raw)
    css_vars, css_props = parse_css(css_raw)

    return Preset(
        name        = name,
        path        = path,
        config_path = config_path,
        style_path  = style_path,
        modules_left   = left,
        modules_center = center,
        modules_right  = right,
        css_vars    = css_vars,
        css_props   = css_props,
        css_raw     = css_raw,
        config_raw  = config_raw,
    )
