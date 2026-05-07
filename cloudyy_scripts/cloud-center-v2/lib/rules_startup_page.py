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


# ── Autostart parse / serialize ────────────────────────────────────────────────

def _parse_autostart(lines: list[str]) -> list[AutostartEntry]:
    entries: list[AutostartEntry] = []
    for line in lines:
        line = line.strip()
        if line.startswith('exec-once'):
            _, _, cmd = line.partition('=')
            entries.append(AutostartEntry(command=cmd.strip(), exec_once=True))
        elif line.startswith('exec'):
            _, _, cmd = line.partition('=')
            entries.append(AutostartEntry(command=cmd.strip(), exec_once=False))
    return entries


def _serialize_autostart(entries: list[AutostartEntry]) -> list[str]:
    return [
        f"{'exec-once' if e.exec_once else 'exec'} = {e.command}"
        for e in entries
    ]


# ── Env var parse / serialize ──────────────────────────────────────────────────

_ENV_NAME_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')


def _valid_env_name(name: str) -> bool:
    return bool(_ENV_NAME_RE.match(name))


def _parse_env_vars(lines: list[str]) -> list[EnvVar]:
    vars_: list[EnvVar] = []
    for line in lines:
        line = line.strip()
        if line.startswith('env'):
            _, _, rest = line.partition('=')
            rest = rest.strip()
            name, _, value = rest.partition(',')
            vars_.append(EnvVar(name=name.strip(), value=value))
    return vars_


def _serialize_env_vars(vars_: list[EnvVar]) -> list[str]:
    return [f'env = {v.name},{v.value}' for v in vars_]


# ── Conf file I/O ──────────────────────────────────────────────────────────────

def _parse_conf(text: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {k: [] for k in _M}
    current: Optional[str] = None
    for line in text.splitlines():
        stripped = line.strip()
        matched = False
        for key, (start, end) in _M.items():
            if stripped == start:
                current = key
                matched = True
                break
            if stripped == end:
                current = None
                matched = True
                break
        if not matched and current is not None:
            result[current].append(line)
    return result


def _write_conf(
    window_rules: list[WindowRule],
    layer_rules: list[LayerRule],
    autostart: list[AutostartEntry],
    env_vars: list[EnvVar],
    path: Path = CONF_PATH,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out: list[str] = []
    for key, serialize_fn, items in [          # type: ignore[var-annotated]
        ('window_rules', _serialize_window_rules, window_rules),
        ('layer_rules',  _serialize_layer_rules,  layer_rules),
        ('autostart',    _serialize_autostart,     autostart),
        ('env_vars',     _serialize_env_vars,      env_vars),
    ]:
        start, end = _M[key]
        out.append(start)
        out.extend(serialize_fn(items))
        out.append(end)
        out.append('')
    tmp = path.with_suffix('.tmp')
    tmp.write_text('\n'.join(out), encoding='utf-8')
    tmp.replace(path)
