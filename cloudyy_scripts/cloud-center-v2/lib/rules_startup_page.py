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


# ── Window rule parse / serialize ──────────────────────────────────────────────

def _parse_window_rules(lines: list[str]) -> list[WindowRule]:
    rules: list[WindowRule] = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == 'windowrule {':
            name = ''
            matchers: list[tuple[str, str]] = []
            effects: dict[str, str] = {}
            i += 1
            while i < len(lines) and lines[i].strip() != '}':
                raw = lines[i].strip()
                if '=' in raw:
                    key, _, val = raw.partition('=')
                    key = key.strip()
                    val = val.strip()
                    if key == 'name':
                        name = val
                    elif key.startswith('match:'):
                        matchers.append((key, val))
                    else:
                        effects[key] = val
                i += 1
            rules.append(WindowRule(name=name, matchers=matchers, effects=effects))
        i += 1
    return rules


def _serialize_window_rules(rules: list[WindowRule]) -> list[str]:
    lines: list[str] = []
    for rule in rules:
        lines.append('windowrule {')
        if rule.name:
            lines.append(f'    name        = {rule.name}')
        for key, val in rule.matchers:
            lines.append(f'    {key} = {val}')
        for effect, val in rule.effects.items():
            lines.append(f'    {effect} = {val}')
        lines.append('}')
        lines.append('')
    return lines


# ── Layer rule parse / serialize ───────────────────────────────────────────────

def _parse_layer_rules(lines: list[str]) -> list[LayerRule]:
    rules: list[LayerRule] = []
    i = 0
    while i < len(lines):
        if lines[i].strip() == 'layerrule {':
            name = ''
            namespace = ''
            effects: dict[str, str] = {}
            i += 1
            while i < len(lines) and lines[i].strip() != '}':
                raw = lines[i].strip()
                if '=' in raw:
                    key, _, val = raw.partition('=')
                    key = key.strip()
                    val = val.strip()
                    if key == 'name':
                        name = val
                    elif key == 'match:namespace':
                        namespace = val
                    else:
                        effects[key] = val
                i += 1
            rules.append(LayerRule(name=name, namespace=namespace, effects=effects))
        i += 1
    return rules


def _serialize_layer_rules(rules: list[LayerRule]) -> list[str]:
    lines: list[str] = []
    for rule in rules:
        lines.append('layerrule {')
        if rule.name:
            lines.append(f'    name            = {rule.name}')
        if rule.namespace:
            lines.append(f'    match:namespace = {rule.namespace}')
        for effect, val in rule.effects.items():
            lines.append(f'    {effect} = {val}')
        lines.append('}')
        lines.append('')
    return lines
