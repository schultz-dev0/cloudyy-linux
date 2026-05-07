"""
Cloud Center — lib/rules_startup_page.py
Rules & Startup page: Window Rules, Layer Rules, Autostart, Environment Variables.
"""
from __future__ import annotations

import json
import logging
import re
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

# ── Paths ──────────────────────────────────────────────────────────────────────

HYPR_DIR  = Path.home() / '.config' / 'hypr'
CONF_PATH = HYPR_DIR / 'user-configs' / 'user_rules_startup.conf'

# Section markers
_M: dict[str, tuple[str, str]] = {
    'window_rules': ('# --- CC: Window Rules ---',  '# --- CC: End Window Rules ---'),
    'layer_rules':  ('# --- CC: Layer Rules ---',   '# --- CC: End Layer Rules ---'),
    'autostart':    ('# --- CC: Autostart ---',      '# --- CC: End Autostart ---'),
    'env_vars':     ('# --- CC: Environment ---',    '# --- CC: End Environment ---'),
}

# ── Data models ────────────────────────────────────────────────────────────────

@dataclass
class WindowRule:
    name: str
    matchers: list[tuple[str, str]]
    effects: dict[str, str]

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, WindowRule):
            return NotImplemented
        return (self.name == other.name
                and self.matchers == other.matchers
                and self.effects == other.effects)


@dataclass
class LayerRule:
    name: str
    namespace: str
    effects: dict[str, str]

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, LayerRule):
            return NotImplemented
        return (self.name == other.name
                and self.namespace == other.namespace
                and self.effects == other.effects)


@dataclass
class AutostartEntry:
    command: str
    exec_once: bool

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, AutostartEntry):
            return NotImplemented
        return self.command == other.command and self.exec_once == other.exec_once


@dataclass
class EnvVar:
    name: str
    value: str

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, EnvVar):
            return NotImplemented
        return self.name == other.name and self.value == other.value
