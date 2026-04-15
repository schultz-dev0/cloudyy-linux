"""
waybar-editor/models.py
Data structures shared across all editor modules.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

log = logging.getLogger(__name__)

WAYBAR_DIR   = Path.home() / ".config" / "waybar"
PRESETS_DIR  = WAYBAR_DIR / "presets"
CURRENT_FILE = WAYBAR_DIR / ".current_preset"


class Position(Enum):
    LEFT   = "left"
    CENTER = "center"
    RIGHT  = "right"


@dataclass
class WaybarModule:
    name:     str       # e.g. "clock", "custom/weather", "pulseaudio#output"
    position: Position
    enabled:  bool = True
    config:   dict[str, object] = field(default_factory=dict)

    @property
    def display_name(self) -> str:
        n = self.name
        if "/" in n:
            n = n.split("/", 1)[1]
        n = n.replace("#", " ").replace("-", " ").replace("_", " ")
        return n.title()

    @property
    def css_id(self) -> str:
        if "#" in self.name:
            base, cls = self.name.split("#", 1)
            return f"#{base}.{cls}"
        base = self.name.split("/")[-1]
        return f"#{base}"


@dataclass
class CSSVar:
    name:  str
    value: str
    line:  int = 0


@dataclass
class CSSProperty:
    selector: str
    prop:     str
    value:    str
    line:     int = 0


@dataclass
class Preset:
    name:        str
    path:        Path
    config_path: Path
    style_path:  Path

    modules_left:   list[WaybarModule] = field(default_factory=list)
    modules_center: list[WaybarModule] = field(default_factory=list)
    modules_right:  list[WaybarModule] = field(default_factory=list)

    css_vars:  list[CSSVar]      = field(default_factory=list)
    css_props: list[CSSProperty] = field(default_factory=list)
    css_raw:    str = ""
    config_raw: str = ""

    @property
    def all_modules(self) -> list[WaybarModule]:
        return self.modules_left + self.modules_center + self.modules_right


def list_presets() -> list[str]:
    if not PRESETS_DIR.exists():
        return []
    return sorted(p.name for p in PRESETS_DIR.iterdir() if p.is_dir())


def current_preset_name() -> str:
    try:
        return CURRENT_FILE.read_text(encoding="utf-8").strip()
    except OSError as e:
        log.warning("Could not read %s, using first preset: %s", CURRENT_FILE, e)
        presets = list_presets()
        return presets[0] if presets else ""
