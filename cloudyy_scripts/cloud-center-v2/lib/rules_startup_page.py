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
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)

from gi.repository import Gtk as _Gtk
from lib import hcm_lua, hyprlua_reader

# ── Paths ──────────────────────────────────────────────────────────────────────

HYPR_DIR = Path.home() / '.config' / 'hypr'
MAIN_LUA = HYPR_DIR / 'hyprland.lua'

WINDOWRULES_CONF_PATH = HYPR_DIR / 'windowrules.lua'
AUTOSTART_CONF_PATH = HYPR_DIR / 'autostart.lua'
VARIABLES_CONF_PATH = HYPR_DIR / 'variables.lua'

SURFACE_PATHS: dict[str, Path] = {
    'windowrules': WINDOWRULES_CONF_PATH,
    'autostart': AUTOSTART_CONF_PATH,
    'variables': VARIABLES_CONF_PATH,
}

# Rules/startup/variables are free-form Lua, so use a distinct marker: Cloud
# Center treats the files as manual overrides and never regenerates their bodies.
MANAGED_STATE_PREFIX = '-- @cloud-center-rules-startup-state = '
MANAGED_BEGIN = '-- --- Cloud Center managed additions ---'
MANAGED_END = '-- --- End Cloud Center managed additions ---'

_IO_LOCK = threading.RLock()

_DIALOG_WIDTH = 560
_DIALOG_HEIGHT = 640
_DIALOG_HEIGHT_COMPACT = 480

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
        elif line.startswith('hl.exec_once(') or line.startswith('hl.exec_cmd('):
            match = re.match(r'hl\.(exec_once|exec_cmd)\((.+)\)', line)
            if not match:
                continue
            try:
                command = json.loads(match.group(2))
            except json.JSONDecodeError:
                continue
            entries.append(AutostartEntry(command=str(command), exec_once=match.group(1) == 'exec_once'))
    return entries


def _serialize_autostart(entries: list[AutostartEntry]) -> list[str]:
    return [
        f'hl.{"exec_once" if e.exec_once else "exec_cmd"}({json.dumps(e.command)})'
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
        elif line.startswith('hl.env('):
            match = re.match(r'hl\.env\((.+?),\s*(.+)\)$', line)
            if not match:
                continue
            try:
                name = json.loads(match.group(1))
                value = json.loads(match.group(2))
            except json.JSONDecodeError:
                continue
            vars_.append(EnvVar(name=str(name), value=str(value)))
    return vars_


def _serialize_env_vars(vars_: list[EnvVar]) -> list[str]:
    return [f'hl.env({json.dumps(v.name)}, {json.dumps(v.value)})' for v in vars_]


# ── Conf file I/O ──────────────────────────────────────────────────────────────

def _state_scalar(value: object) -> str:
    if isinstance(value, bool):
        return 'on' if value else 'off'
    if value is None:
        return ''
    if isinstance(value, str):
        if value == 'true':
            return 'on'
        if value == 'false':
            return 'off'
        return value
    return str(value)


def _state_bool(value: object, default: bool = True) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        if value.lower() in {'false', 'off', '0', 'no'}:
            return False
        if value.lower() in {'true', 'on', '1', 'yes'}:
            return True
    return default


def _window_rule_from_state(item: object) -> WindowRule:
    if not isinstance(item, dict):
        return WindowRule(name='', matchers=[], effects={})

    matchers: list[tuple[str, str]] = []
    raw_matchers = item.get('matchers', [])
    if isinstance(raw_matchers, list):
        for matcher in raw_matchers:
            if isinstance(matcher, (list, tuple)) and len(matcher) == 2:
                matchers.append((_state_scalar(matcher[0]), _state_scalar(matcher[1])))
    raw_match = item.get('match', {})
    if not matchers and isinstance(raw_match, dict):
        matchers = [(f'match:{key}', _state_scalar(value)) for key, value in raw_match.items()]

    raw_effects = item.get('effects', {})
    effects = (
        {str(key): _state_scalar(value) for key, value in raw_effects.items()}
        if isinstance(raw_effects, dict) else {}
    )
    # Early Rules & Startup builds stored the rendered rule as a flat object
    # (`match`, `float`, `size`, …) rather than matchers/effects.  Accept both
    # shapes so those installations migrate without silently losing fields.
    for key, value in item.items():
        if key not in {'name', 'match', 'matchers', 'effects'}:
            effects.setdefault(str(key), _state_scalar(value))

    return WindowRule(
        name=_state_scalar(item.get('name', '')),
        matchers=matchers,
        effects=effects,
    )


def _layer_rule_from_state(item: object) -> LayerRule:
    if not isinstance(item, dict):
        return LayerRule(name='', namespace='', effects={})

    namespace = _state_scalar(item.get('namespace', ''))
    raw_match = item.get('match', {})
    if not namespace and isinstance(raw_match, dict):
        namespace = _state_scalar(raw_match.get('namespace', ''))

    raw_effects = item.get('effects', {})
    effects = (
        {str(key): _state_scalar(value) for key, value in raw_effects.items()}
        if isinstance(raw_effects, dict) else {}
    )
    for key, value in item.items():
        if key not in {'name', 'namespace', 'match', 'effects'}:
            effects.setdefault(str(key), _state_scalar(value))

    return LayerRule(
        name=_state_scalar(item.get('name', '')),
        namespace=namespace,
        effects=effects,
    )


def _state_sections(data: object) -> dict[str, list[str]]:
    if not isinstance(data, dict):
        data = {}
    return {
        'window_rules': _serialize_window_rules([
            _window_rule_from_state(item) for item in data.get('window_rules', [])
        ]),
        'layer_rules': _serialize_layer_rules([
            _layer_rule_from_state(item) for item in data.get('layer_rules', [])
        ]),
        'autostart': [
            f"{'exec-once' if _state_bool(item.get('exec_once', True)) else 'exec'} = "
            f"{_state_scalar(item.get('command', ''))}"
            for item in data.get('autostart', []) if isinstance(item, dict)
        ],
        'env_vars': [
            f"env = {_state_scalar(item.get('name', ''))},{_state_scalar(item.get('value', ''))}"
            for item in data.get('env_vars', []) if isinstance(item, dict)
        ],
    }


def _parse_conf(text: str) -> dict[str, list[str]]:
    for line in text.splitlines()[:10]:
        if not line.startswith(MANAGED_STATE_PREFIX):
            continue
        try:
            return _state_sections(json.loads(line[len(MANAGED_STATE_PREFIX):]))
        except json.JSONDecodeError:
            log.warning('Invalid Rules & Startup state sentinel')

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


_NUMBER_RE = re.compile(r'^-?(?:\d+\.\d+|\d+|\.\d+)$')


def _lua_value(value: str) -> str:
    if value in {'on', 'true'}:
        return 'true'
    if value in {'off', 'false'}:
        return 'false'
    if _NUMBER_RE.match(value):
        return value
    return json.dumps(value)


def _render_window_rules_lua(rules: list[WindowRule]) -> list[str]:
    lines: list[str] = []
    matcher_key_map = {
        'match:class': 'class',
        'match:title': 'title',
        'match:tag': 'tag',
        'match:xwayland': 'xwayland',
        'match:float': 'float',
        'match:fullscreen': 'fullscreen',
    }
    for rule in rules:
        lines.append('hl.window_rule({')
        if rule.name:
            lines.append(f'    name = {json.dumps(rule.name)},')
        if rule.matchers:
            lines.append('    match = {')
            for key, val in rule.matchers:
                lines.append(f'        {matcher_key_map.get(key, key.replace("match:", ""))} = {_lua_value(val)},')
            lines.append('    },')
        for effect, val in rule.effects.items():
            lines.append(f'    {effect} = {_lua_value(val)},')
        lines.append('})')
        lines.append('')
    return lines


def _render_layer_rules_lua(rules: list[LayerRule]) -> list[str]:
    lines: list[str] = []
    for rule in rules:
        lines.append('hl.layer_rule({')
        if rule.name:
            lines.append(f'    name = {json.dumps(rule.name)},')
        if rule.namespace:
            lines.append('    match = {')
            lines.append(f'        namespace = {_lua_value(rule.namespace)},')
            lines.append('    },')
        for effect, val in rule.effects.items():
            lines.append(f'    {effect} = {_lua_value(val)},')
        lines.append('})')
        lines.append('')
    return lines


def _atomic_write(path: Path, text: str) -> None:
    # windowrules.lua/autostart.lua/variables.lua have no distro fallback to
    # recover from a torn write, so this delegates to hcm_lua's fsync'd
    # mkstemp+replace pattern instead of a plain write_text+replace.
    hcm_lua.atomic_write(path, text)


def _snapshot(path: Path) -> bytes | None:
    return path.read_bytes() if path.exists() else None


def _restore_snapshot(path: Path, content: bytes | None) -> None:
    if content is None:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f'{path.name}.rollback')
    tmp.write_bytes(content)
    tmp.replace(path)


def _surface_state(
    surface: str,
    window_rules: list[WindowRule],
    layer_rules: list[LayerRule],
    autostart: list[AutostartEntry],
    env_vars: list[EnvVar],
) -> dict[str, list[dict]]:
    if surface == 'windowrules':
        return {
            'window_rules': [
                {'name': rule.name, 'matchers': list(rule.matchers), 'effects': rule.effects}
                for rule in window_rules
            ],
            'layer_rules': [
                {'name': rule.name, 'namespace': rule.namespace, 'effects': rule.effects}
                for rule in layer_rules
            ],
        }
    if surface == 'autostart':
        return {
            'autostart': [
                {'command': entry.command, 'exec_once': entry.exec_once}
                for entry in autostart
            ],
        }
    if surface == 'variables':
        return {
            'env_vars': [{'name': var.name, 'value': var.value} for var in env_vars],
        }
    raise ValueError(f'Unknown Rules & Startup surface: {surface}')


def _surface_managed_lines(
    surface: str,
    window_rules: list[WindowRule],
    layer_rules: list[LayerRule],
    autostart: list[AutostartEntry],
    env_vars: list[EnvVar],
) -> list[str]:
    if surface == 'windowrules':
        return _render_window_rules_lua(window_rules) + _render_layer_rules_lua(layer_rules)
    if surface == 'autostart':
        return _serialize_autostart(autostart)
    if surface == 'variables':
        return _serialize_env_vars(env_vars)
    raise ValueError(f'Unknown Rules & Startup surface: {surface}')


def _render_surface_text(
    existing: str,
    surface: str,
    state: dict[str, list[dict]],
    managed_lines: list[str],
) -> str:
    """Replace only Cloud Center metadata/managed lines; preserve manual Lua."""
    lines = existing.splitlines()
    body: list[str] = []
    found_managed = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if line == MANAGED_BEGIN:
            if found_managed:
                raise ValueError(f'Duplicate managed section in {surface}.lua')
            found_managed = True
            body.append(MANAGED_BEGIN)
            body.extend(managed_lines)
            while body and body[-1] == '':
                body.pop()
            body.append(MANAGED_END)
            i += 1
            while i < len(lines) and lines[i] != MANAGED_END:
                i += 1
            if i == len(lines):
                raise ValueError(f'Unterminated managed section in {surface}.lua')
            i += 1
            continue
        if line == MANAGED_END:
            raise ValueError(f'Unexpected managed section end in {surface}.lua')
        if (
            line.startswith(MANAGED_STATE_PREFIX)
            or line.startswith('-- Cloud Center user override file for ')
        ):
            i += 1
            continue
        body.append(line)
        i += 1

    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()

    if not found_managed:
        if body:
            body.append('')
        body.append(MANAGED_BEGIN)
        body.extend(managed_lines)
        while body and body[-1] == '':
            body.pop()
        body.append(MANAGED_END)

    out = [
        f'{MANAGED_STATE_PREFIX}{json.dumps(state, sort_keys=True)}',
        '',
        *body,
    ]
    return '\n'.join(out).rstrip() + '\n'


def _unmanaged_body(text: str) -> str:
    """Content outside Cloud Center metadata/managed markers."""
    body: list[str] = []
    in_managed = False
    for line in text.splitlines():
        if line == MANAGED_BEGIN:
            in_managed = True
            continue
        if line == MANAGED_END:
            in_managed = False
            continue
        if in_managed:
            continue
        if (
            line.startswith(MANAGED_STATE_PREFIX)
            or line.startswith('-- Cloud Center user override file for ')
        ):
            continue
        body.append(line)
    return '\n'.join(body).strip()


def _read_surface_sections(path: Path) -> dict[str, list[str]]:
    if not path.exists():
        return {key: [] for key in _M}
    return _parse_conf(path.read_text(encoding='utf-8'))


def _write_surface(
    surface: str,
    window_rules: list[WindowRule],
    layer_rules: list[LayerRule],
    autostart: list[AutostartEntry],
    env_vars: list[EnvVar],
    *,
    path_override: Path | None = None,
) -> None:
    path = path_override or SURFACE_PATHS[surface]
    old = _snapshot(path)
    existing = old.decode('utf-8') if old is not None else ''
    state = _surface_state(surface, window_rules, layer_rules, autostart, env_vars)
    managed_lines = _surface_managed_lines(
        surface, window_rules, layer_rules, autostart, env_vars
    )
    try:
        rendered = _render_surface_text(existing, surface, state, managed_lines)
        _atomic_write(path, rendered)
    except Exception:
        _restore_snapshot(path, old)
        raise


def _write_conf(
    window_rules: list[WindowRule],
    layer_rules: list[LayerRule],
    autostart: list[AutostartEntry],
    env_vars: list[EnvVar],
    path: Path | None = None,
    *,
    surfaces: set[str] | None = None,
) -> None:
    """Write only the touched surfaces, never the old combined file."""
    with _IO_LOCK:
        if path is not None:
            _write_surface(
                'variables', window_rules, layer_rules, autostart, env_vars,
                path_override=path,
            )
            return

        if surfaces is None:
            selected = {
                surface for surface, user_path in SURFACE_PATHS.items()
                if user_path.exists()
            }
            if window_rules or layer_rules:
                selected.add('windowrules')
            if autostart:
                selected.add('autostart')
            if env_vars:
                selected.add('variables')
        else:
            selected = set(surfaces)

        for surface in ('windowrules', 'autostart', 'variables'):
            if surface in selected:
                _write_surface(
                    surface, window_rules, layer_rules, autostart, env_vars
                )


def _dataclass_window_rules(text: str) -> list[WindowRule]:
    return [WindowRule(**item) for item in hyprlua_reader.parse_window_rules(text)]


def _dataclass_layer_rules(text: str) -> list[LayerRule]:
    return [LayerRule(**item) for item in hyprlua_reader.parse_layer_rules(text)]


def _dataclass_autostart(text: str) -> list[AutostartEntry]:
    return [AutostartEntry(**item) for item in hyprlua_reader.parse_autostart(text)]


def _dataclass_env_vars(text: str) -> list[EnvVar]:
    return [EnvVar(**item) for item in hyprlua_reader.parse_env_vars(text)]


def _configure_dialog(dialog, *, width: int = _DIALOG_WIDTH, height: int = _DIALOG_HEIGHT) -> None:
    dialog.set_content_width(width)
    dialog.set_content_height(height)


def upsert_env_vars(updates: dict[str, str], path: Path | None = None) -> None:
    with _IO_LOCK:
        target = path or VARIABLES_CONF_PATH
        sections = _read_surface_sections(target)
        env_vars = _parse_env_vars(sections['env_vars'])

    by_name = {var.name: var for var in env_vars}
    for name, value in updates.items():
        by_name[name] = EnvVar(name=name, value=value)

    merged_env_vars: list[EnvVar] = []
    seen: set[str] = set()
    for var in env_vars:
        merged = by_name[var.name]
        if merged.name not in seen:
            merged_env_vars.append(merged)
            seen.add(merged.name)
    for name, var in by_name.items():
        if name not in seen:
            merged_env_vars.append(var)

    _write_conf([], [], [], merged_env_vars, path=path, surfaces={'variables'})


# ── GTK import helper ──────────────────────────────────────────────────────────
# Deferred so parse/serialize tests can import this module without a display.

def _gtk_imports():
    from gi.repository import Adw, Gdk, GLib, Gtk, Pango
    return Adw, Gdk, GLib, Gtk, Pango


def _present_dialog(dialog, parent_widget) -> None:
    """Present an Adw.Dialog with a proper top-level window parent."""
    _, _, _, Gtk, _ = _gtk_imports()
    root = parent_widget.get_root() if parent_widget is not None else None
    if isinstance(root, Gtk.Window):
        dialog.present(root)
    elif parent_widget is not None:
        dialog.present(parent_widget)
    else:
        dialog.present()


# ── Window Picker Dialog ───────────────────────────────────────────────────────

class _WindowPickerDialog:
    """Lists running Hyprland windows; calls on_pick(window_class) on select."""

    def __init__(self, parent_widget, on_pick) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._on_pick = on_pick

        self._dialog = Adw.Dialog()
        self._dialog.set_title('Pick a Window')
        _configure_dialog(self._dialog, width=480, height=_DIALOG_HEIGHT_COMPACT)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Adw.HeaderBar()
        header.add_css_class('flat')
        outer.append(header)

        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.add_css_class('boxed-list')
        self._list.set_margin_start(12)
        self._list.set_margin_end(12)
        self._list.set_margin_top(8)
        self._list.set_margin_bottom(12)
        self._list.connect('row-activated', self._on_row_activated)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(self._list)
        outer.append(scroll)

        self._dialog.set_child(outer)
        _present_dialog(self._dialog, parent_widget)
        threading.Thread(target=self._load_windows, daemon=True).start()

    def _load_windows(self) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        try:
            result = subprocess.run(
                ['hyprctl', 'clients', '-j'],
                capture_output=True, text=True, timeout=3,
            )
            clients = json.loads(result.stdout)
        except Exception:
            clients = []
        GLib.idle_add(self._populate, clients)

    def _populate(self, clients: list) -> bool:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        if not clients:
            row = Adw.ActionRow()
            row.set_title('Could not list windows')
            row.set_subtitle('Is Hyprland running?')
            self._list.append(row)
            return GLib.SOURCE_REMOVE
        for c in clients:
            cls   = c.get('class', '')
            title = c.get('title', '')
            if not cls:
                continue
            row = Adw.ActionRow()
            row.set_title(cls)
            row.set_subtitle(title[:80] if title else '')
            row._window_class = cls  # type: ignore[attr-defined]
            self._list.append(row)
        return GLib.SOURCE_REMOVE

    def _on_row_activated(self, _listbox, row) -> None:
        cls = getattr(row, '_window_class', None)
        if cls:
            self._on_pick(cls)
        self._dialog.close()


# ── Window Rule Dialog ─────────────────────────────────────────────────────────

_WR_MATCHER_KEYS: list[str] = [
    'match:class', 'match:title', 'match:tag',
    'match:xwayland', 'match:float', 'match:fullscreen',
]
_WR_TOGGLE_EFFECTS: list[str] = ['float', 'opaque', 'center', 'pin', 'noblur', 'immediate']
_WR_VALUE_EFFECTS: dict[str, str] = {
    'opacity': '0.0–1.0, e.g. 0.9',
    'size':    'width height, e.g. 1080 720',
}


class _WindowRuleDialog:
    """Add/edit a single WindowRule. Calls on_save(WindowRule) on confirm."""

    def __init__(self, parent_widget, on_save, existing: Optional[WindowRule] = None) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._on_save = on_save
        self._parent  = parent_widget
        self._matcher_rows: list[tuple] = []   # (row_box, Gtk.DropDown, Gtk.Entry)
        is_edit = existing is not None

        self._dialog = Adw.Dialog()
        self._dialog.set_title('Edit Rule' if is_edit else 'Add Rule')
        _configure_dialog(self._dialog)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Adw.HeaderBar()
        header.add_css_class('flat')
        outer.append(header)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(12)
        content.set_margin_bottom(16)
        scroll.set_child(content)
        outer.append(scroll)

        # Name
        name_group = Adw.PreferencesGroup()
        name_group.set_title('Name (optional)')
        self._name_entry = Adw.EntryRow()
        self._name_entry.set_title('Rule name')
        name_group.add(self._name_entry)
        content.append(name_group)

        # Matchers
        self._matchers_group = Adw.PreferencesGroup()
        self._matchers_group.set_title('Matchers')
        self._matchers_group.set_description('At least one matcher required')
        self._matchers_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._matchers_group.add(self._matchers_box)
        add_matcher_btn = Gtk.Button(label='+ Add matcher')
        add_matcher_btn.add_css_class('flat')
        add_matcher_btn.add_css_class('accent')
        add_matcher_btn.set_halign(Gtk.Align.START)
        add_matcher_btn.connect('clicked', lambda _: self._add_matcher_row())
        self._matchers_group.add(add_matcher_btn)
        content.append(self._matchers_group)

        # Effects
        effects_group = Adw.PreferencesGroup()
        effects_group.set_title('Effects')
        self._effect_switches: dict[str, Adw.SwitchRow] = {}
        self._effect_entries:  dict[str, Adw.EntryRow]  = {}

        for eff in _WR_TOGGLE_EFFECTS:
            row = Adw.SwitchRow()
            row.set_title(eff)
            self._effect_switches[eff] = row
            effects_group.add(row)
            row.connect('notify::active', lambda *_: self._update_preview())

        for eff, placeholder in _WR_VALUE_EFFECTS.items():
            sw = Adw.SwitchRow()
            sw.set_title(eff)
            self._effect_switches[eff] = sw
            effects_group.add(sw)

            entry = Adw.EntryRow()
            entry.set_title(placeholder)
            entry.set_visible(False)
            self._effect_entries[eff] = entry
            effects_group.add(entry)

            sw.connect(
                'notify::active',
                lambda s, _p, e=eff: (
                    self._effect_entries[e].set_visible(s.get_active()),
                    self._update_preview(),
                ),
            )
            entry.connect('changed', lambda *_: self._update_preview())

        content.append(effects_group)

        # Live preview
        preview_group = Adw.PreferencesGroup()
        preview_group.set_title('Preview')
        self._preview_label = Gtk.Label()
        self._preview_label.set_wrap(True)
        self._preview_label.set_xalign(0)
        self._preview_label.add_css_class('monospace')
        self._preview_label.add_css_class('dim-label')
        self._preview_label.set_margin_start(8)
        self._preview_label.set_margin_end(8)
        self._preview_label.set_margin_top(6)
        self._preview_label.set_margin_bottom(6)
        preview_group.add(self._preview_label)
        content.append(preview_group)

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_box.set_halign(Gtk.Align.END)
        btn_box.set_margin_top(4)
        cancel_btn = Gtk.Button(label='Cancel')
        cancel_btn.connect('clicked', lambda _: self._dialog.close())
        self._save_btn = Gtk.Button(label='Save' if is_edit else 'Add Rule')
        self._save_btn.add_css_class('suggested-action')
        self._save_btn.connect('clicked', self._on_save_clicked)
        btn_box.append(cancel_btn)
        btn_box.append(self._save_btn)
        content.append(btn_box)

        self._dialog.set_child(outer)

        if existing:
            self._name_entry.set_text(existing.name)
            for key, val in existing.matchers:
                self._add_matcher_row(key, val)
            for eff, val in existing.effects.items():
                if eff in self._effect_switches:
                    self._effect_switches[eff].set_active(True)
                if eff in self._effect_entries:
                    self._effect_entries[eff].set_text(val)
                    self._effect_entries[eff].set_visible(True)
        else:
            self._add_matcher_row()

        self._name_entry.connect('changed', lambda *_: self._update_preview())
        self._update_preview()
        _present_dialog(self._dialog, parent_widget)

    def _add_matcher_row(self, key: str = 'match:class', val: str = '') -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        row_box.set_margin_bottom(4)

        model = Gtk.StringList.new(None)
        for k in _WR_MATCHER_KEYS:
            model.append(k)
        dropdown = Gtk.DropDown(model=model)
        dropdown.set_size_request(150, -1)
        if key in _WR_MATCHER_KEYS:
            dropdown.set_selected(_WR_MATCHER_KEYS.index(key))

        val_entry = Gtk.Entry()
        val_entry.set_text(val)
        val_entry.set_hexpand(True)
        val_entry.set_placeholder_text('regex value')

        pick_btn = Gtk.Button(label='Pick')
        pick_btn.add_css_class('flat')
        pick_btn.connect('clicked', lambda _, e=val_entry: self._pick_window(e))

        rm_btn = Gtk.Button(icon_name='list-remove-symbolic')
        rm_btn.add_css_class('flat')
        rm_btn.add_css_class('destructive-action')
        rm_btn.connect('clicked', lambda _, rb=row_box: self._remove_matcher_row(rb))

        row_box.append(dropdown)
        row_box.append(val_entry)
        row_box.append(pick_btn)
        row_box.append(rm_btn)
        self._matchers_box.append(row_box)
        self._matcher_rows.append((row_box, dropdown, val_entry))

        dropdown.connect('notify::selected', lambda *_: self._update_preview())
        val_entry.connect('changed', lambda *_: self._update_preview())
        self._update_preview()

    def _remove_matcher_row(self, row_box) -> None:
        self._matchers_box.remove(row_box)
        # Filter by row_box.get_parent() — after removal row_box.get_parent() is None,
        # while dropdown.get_parent() would still return the orphaned row_box (not None).
        self._matcher_rows = [(rb, d, e) for (rb, d, e) in self._matcher_rows if rb.get_parent() is not None]
        self._update_preview()

    def _pick_window(self, entry) -> None:
        _WindowPickerDialog(self._dialog, lambda cls: entry.set_text(f'^({cls})$'))

    def _collect(self) -> tuple[str, list[tuple[str, str]], dict[str, str]]:
        name = self._name_entry.get_text().strip()
        matchers = [
            (_WR_MATCHER_KEYS[d.get_selected()], e.get_text().strip())
            for _rb, d, e in self._matcher_rows
            if e.get_text().strip()
        ]
        effects: dict[str, str] = {}
        for eff, sw in self._effect_switches.items():
            if sw.get_active():
                effects[eff] = (
                    self._effect_entries[eff].get_text().strip()
                    if eff in self._effect_entries else 'on'
                )
        return name, matchers, effects

    def _update_preview(self) -> None:
        name, matchers, effects = self._collect()
        lines = ['windowrule {']
        if name:
            lines.append(f'    name = {name}')
        for k, v in matchers:
            lines.append(f'    {k} = {v}')
        for eff, val in effects.items():
            lines.append(f'    {eff} = {val}')
        lines.append('}')
        self._preview_label.set_text('\n'.join(lines))
        self._save_btn.set_sensitive(bool(matchers))

    def _on_save_clicked(self, _btn) -> None:
        name, matchers, effects = self._collect()
        if not matchers:
            return
        self._on_save(WindowRule(name=name, matchers=matchers, effects=effects))
        self._dialog.close()


# ── Layer Rule Dialog ──────────────────────────────────────────────────────────

_LR_TOGGLE_EFFECTS: list[str] = ['blur', 'dim_around', 'xray', 'no_anim']
_LR_VALUE_EFFECTS: dict[str, str] = {
    'ignore_alpha': '0.0–1.0, e.g. 0.2',
    'animation':    'e.g. slide down',
}


class _LayerRuleDialog:
    """Add/edit a single LayerRule. Calls on_save(LayerRule) on confirm."""

    def __init__(self, parent_widget, on_save, existing: Optional[LayerRule] = None) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._on_save = on_save
        is_edit = existing is not None

        self._dialog = Adw.Dialog()
        self._dialog.set_title('Edit Layer Rule' if is_edit else 'Add Layer Rule')
        _configure_dialog(self._dialog)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Adw.HeaderBar()
        header.add_css_class('flat')
        outer.append(header)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(12)
        content.set_margin_bottom(16)
        scroll.set_child(content)
        outer.append(scroll)

        name_group = Adw.PreferencesGroup()
        name_group.set_title('Name (optional)')
        self._name_entry = Adw.EntryRow()
        self._name_entry.set_title('Rule name')
        name_group.add(self._name_entry)
        content.append(name_group)

        ns_group = Adw.PreferencesGroup()
        ns_group.set_title('Namespace')
        self._ns_entry = Adw.EntryRow()
        self._ns_entry.set_title('match:namespace regex, e.g. ^(waybar)$')
        ns_group.add(self._ns_entry)
        content.append(ns_group)

        effects_group = Adw.PreferencesGroup()
        effects_group.set_title('Effects')
        self._effect_switches: dict[str, Adw.SwitchRow] = {}
        self._effect_entries:  dict[str, Adw.EntryRow]  = {}

        for eff in _LR_TOGGLE_EFFECTS:
            row = Adw.SwitchRow()
            row.set_title(eff)
            self._effect_switches[eff] = row
            effects_group.add(row)
            row.connect('notify::active', lambda *_: self._update_preview())

        for eff, placeholder in _LR_VALUE_EFFECTS.items():
            sw = Adw.SwitchRow()
            sw.set_title(eff)
            self._effect_switches[eff] = sw
            effects_group.add(sw)
            entry = Adw.EntryRow()
            entry.set_title(placeholder)
            entry.set_visible(False)
            self._effect_entries[eff] = entry
            effects_group.add(entry)
            sw.connect(
                'notify::active',
                lambda s, _p, e=eff: (
                    self._effect_entries[e].set_visible(s.get_active()),
                    self._update_preview(),
                ),
            )
            entry.connect('changed', lambda *_: self._update_preview())

        content.append(effects_group)

        preview_group = Adw.PreferencesGroup()
        preview_group.set_title('Preview')
        self._preview_label = Gtk.Label()
        self._preview_label.set_wrap(True)
        self._preview_label.set_xalign(0)
        self._preview_label.add_css_class('monospace')
        self._preview_label.add_css_class('dim-label')
        self._preview_label.set_margin_start(8)
        self._preview_label.set_margin_end(8)
        self._preview_label.set_margin_top(6)
        self._preview_label.set_margin_bottom(6)
        preview_group.add(self._preview_label)
        content.append(preview_group)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_box.set_halign(Gtk.Align.END)
        cancel_btn = Gtk.Button(label='Cancel')
        cancel_btn.connect('clicked', lambda _: self._dialog.close())
        self._save_btn = Gtk.Button(label='Save' if is_edit else 'Add Rule')
        self._save_btn.add_css_class('suggested-action')
        self._save_btn.connect('clicked', self._on_save_clicked)
        btn_box.append(cancel_btn)
        btn_box.append(self._save_btn)
        content.append(btn_box)

        self._dialog.set_child(outer)

        if existing:
            self._name_entry.set_text(existing.name)
            self._ns_entry.set_text(existing.namespace)
            for eff, val in existing.effects.items():
                if eff in self._effect_switches:
                    self._effect_switches[eff].set_active(True)
                if eff in self._effect_entries:
                    self._effect_entries[eff].set_text(val)
                    self._effect_entries[eff].set_visible(True)

        self._name_entry.connect('changed', lambda *_: self._update_preview())
        self._ns_entry.connect('changed', lambda *_: self._update_preview())
        self._update_preview()
        _present_dialog(self._dialog, parent_widget)

    def _collect(self) -> tuple[str, str, dict[str, str]]:
        name      = self._name_entry.get_text().strip()
        namespace = self._ns_entry.get_text().strip()
        effects: dict[str, str] = {}
        for eff, sw in self._effect_switches.items():
            if sw.get_active():
                effects[eff] = (
                    self._effect_entries[eff].get_text().strip()
                    if eff in self._effect_entries else 'on'
                )
        return name, namespace, effects

    def _update_preview(self) -> None:
        name, namespace, effects = self._collect()
        lines = ['layerrule {']
        if name:
            lines.append(f'    name = {name}')
        if namespace:
            lines.append(f'    match:namespace = {namespace}')
        for eff, val in effects.items():
            lines.append(f'    {eff} = {val}')
        lines.append('}')
        self._preview_label.set_text('\n'.join(lines))
        self._save_btn.set_sensitive(bool(namespace))

    def _on_save_clicked(self, _btn) -> None:
        name, namespace, effects = self._collect()
        if not namespace:
            return
        self._on_save(LayerRule(name=name, namespace=namespace, effects=effects))
        self._dialog.close()


# ── App Picker Dialog ──────────────────────────────────────────────────────────

class _AppPickerDialog:
    """Lists installed .desktop apps; calls on_pick(exec_command) on select."""

    _DESKTOP_DIRS = [
        Path('/usr/share/applications'),
        Path.home() / '.local' / 'share' / 'applications',
    ]

    def __init__(self, parent_widget, on_pick) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._on_pick = on_pick
        self._filter_text = ''

        self._dialog = Adw.Dialog()
        self._dialog.set_title('Pick Application')
        _configure_dialog(self._dialog, width=480, height=_DIALOG_HEIGHT_COMPACT)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Adw.HeaderBar()
        header.add_css_class('flat')
        outer.append(header)

        search = Gtk.SearchEntry()
        search.set_placeholder_text('Filter apps…')
        search.set_margin_start(12)
        search.set_margin_end(12)
        search.set_margin_bottom(6)
        outer.append(search)

        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.add_css_class('boxed-list')
        self._list.set_filter_func(lambda row, _: self._filter(row))
        self._list.connect('row-activated', self._on_row_activated)

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_margin_start(12)
        scroll.set_margin_end(12)
        scroll.set_margin_bottom(12)
        scroll.set_child(self._list)
        outer.append(scroll)

        search.connect('search-changed', lambda s: (
            setattr(self, '_filter_text', s.get_text().lower()) or
            self._list.invalidate_filter()
        ))

        self._dialog.set_child(outer)
        _present_dialog(self._dialog, parent_widget)
        threading.Thread(target=self._load_apps, daemon=True).start()

    def _filter(self, row) -> bool:
        return not self._filter_text or self._filter_text in getattr(row, '_app_name', '').lower()

    def _load_apps(self) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        apps: list[tuple[str, str]] = []
        for d in self._DESKTOP_DIRS:
            if not d.exists():
                continue
            for desktop in sorted(d.glob('*.desktop')):
                try:
                    text = desktop.read_text(encoding='utf-8', errors='replace')
                except OSError:
                    continue
                name = exec_cmd = ''
                for line in text.splitlines():
                    if line.startswith('Name=') and not name:
                        name = line[5:].strip()
                    if line.startswith('Exec=') and not exec_cmd:
                        exec_cmd = re.sub(r'\s*%\w', '', line[5:].strip()).strip()
                if name and exec_cmd:
                    apps.append((name, exec_cmd))
        apps.sort(key=lambda x: x[0].lower())
        GLib.idle_add(self._populate, apps)

    def _populate(self, apps: list[tuple[str, str]]) -> bool:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        for name, exec_cmd in apps:
            row = Adw.ActionRow()
            row.set_title(name)
            row.set_subtitle(exec_cmd)
            row._app_name = name       # type: ignore[attr-defined]
            row._exec_cmd = exec_cmd   # type: ignore[attr-defined]
            self._list.append(row)
        return GLib.SOURCE_REMOVE

    def _on_row_activated(self, _listbox, row) -> None:
        cmd = getattr(row, '_exec_cmd', '')
        if cmd:
            self._on_pick(cmd)
        self._dialog.close()


# ── Autostart Dialog ───────────────────────────────────────────────────────────

class _AutostartDialog:
    """Add/edit a single AutostartEntry. Calls on_save(AutostartEntry) on confirm."""

    def __init__(self, parent_widget, on_save, existing: Optional[AutostartEntry] = None) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._on_save = on_save
        is_edit = existing is not None

        self._dialog = Adw.Dialog()
        self._dialog.set_title('Edit Autostart Entry' if is_edit else 'Add Autostart Entry')
        _configure_dialog(self._dialog, height=_DIALOG_HEIGHT_COMPACT)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Adw.HeaderBar()
        header.add_css_class('flat')
        outer.append(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(12)
        content.set_margin_bottom(16)
        outer.append(content)

        cmd_group = Adw.PreferencesGroup()
        cmd_group.set_title('Command')

        self._cmd_entry = Adw.EntryRow()
        self._cmd_entry.set_title('Command to run at startup')
        cmd_group.add(self._cmd_entry)

        pick_row = Adw.ActionRow()
        pick_row.set_title('Pick installed app')
        pick_btn = Gtk.Button(label='Browse…')
        pick_btn.add_css_class('flat')
        pick_btn.set_valign(Gtk.Align.CENTER)
        pick_btn.connect('clicked', lambda _: _AppPickerDialog(
            self._dialog, lambda cmd: self._cmd_entry.set_text(cmd)
        ))
        pick_row.add_suffix(pick_btn)
        pick_row.set_activatable_widget(pick_btn)
        cmd_group.add(pick_row)
        content.append(cmd_group)

        exec_group = Adw.PreferencesGroup()
        self._exec_once_row = Adw.SwitchRow()
        self._exec_once_row.set_title('Run once at startup')
        self._exec_once_row.set_subtitle('Off = re-run on every Hyprland reload')
        self._exec_once_row.set_active(True)
        exec_group.add(self._exec_once_row)
        content.append(exec_group)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_box.set_halign(Gtk.Align.END)
        cancel_btn = Gtk.Button(label='Cancel')
        cancel_btn.connect('clicked', lambda _: self._dialog.close())
        self._save_btn = Gtk.Button(label='Save' if is_edit else 'Add')
        self._save_btn.add_css_class('suggested-action')
        self._save_btn.connect('clicked', self._on_save_clicked)
        btn_box.append(cancel_btn)
        btn_box.append(self._save_btn)
        content.append(btn_box)

        self._dialog.set_child(outer)

        if existing:
            self._cmd_entry.set_text(existing.command)
            self._exec_once_row.set_active(existing.exec_once)

        _present_dialog(self._dialog, parent_widget)

    def _on_save_clicked(self, _btn) -> None:
        cmd = self._cmd_entry.get_text().strip()
        if not cmd:
            return
        self._on_save(AutostartEntry(command=cmd, exec_once=self._exec_once_row.get_active()))
        self._dialog.close()


# ── Env Var Dialog ─────────────────────────────────────────────────────────────

class _EnvVarDialog:
    """Add/edit a single EnvVar. Calls on_save(EnvVar) on confirm."""

    def __init__(self, parent_widget, on_save, existing: Optional[EnvVar] = None) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._on_save = on_save
        is_edit = existing is not None

        self._dialog = Adw.Dialog()
        self._dialog.set_title('Edit Variable' if is_edit else 'Add Variable')
        _configure_dialog(self._dialog, height=420)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header = Adw.HeaderBar()
        header.add_css_class('flat')
        outer.append(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(12)
        content.set_margin_bottom(16)
        outer.append(content)

        fields_group = Adw.PreferencesGroup()
        self._name_entry = Adw.EntryRow()
        self._name_entry.set_title('Variable name (e.g. XCURSOR_THEME)')
        fields_group.add(self._name_entry)
        self._val_entry = Adw.EntryRow()
        self._val_entry.set_title('Value')
        fields_group.add(self._val_entry)
        content.append(fields_group)

        self._error_label = Gtk.Label()
        self._error_label.add_css_class('error')
        self._error_label.set_xalign(0)
        self._error_label.set_visible(False)
        content.append(self._error_label)

        preview_group = Adw.PreferencesGroup()
        preview_group.set_title('Preview')
        self._preview_label = Gtk.Label()
        self._preview_label.set_xalign(0)
        self._preview_label.add_css_class('monospace')
        self._preview_label.add_css_class('dim-label')
        self._preview_label.set_margin_start(8)
        self._preview_label.set_margin_top(6)
        self._preview_label.set_margin_bottom(6)
        preview_group.add(self._preview_label)
        content.append(preview_group)

        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        btn_box.set_halign(Gtk.Align.END)
        cancel_btn = Gtk.Button(label='Cancel')
        cancel_btn.connect('clicked', lambda _: self._dialog.close())
        self._save_btn = Gtk.Button(label='Save' if is_edit else 'Add')
        self._save_btn.add_css_class('suggested-action')
        self._save_btn.connect('clicked', self._on_save_clicked)
        btn_box.append(cancel_btn)
        btn_box.append(self._save_btn)
        content.append(btn_box)

        self._dialog.set_child(outer)

        if existing:
            self._name_entry.set_text(existing.name)
            self._val_entry.set_text(existing.value)

        self._name_entry.connect('changed', lambda *_: self._update_preview())
        self._val_entry.connect('changed',  lambda *_: self._update_preview())
        self._update_preview()
        _present_dialog(self._dialog, parent_widget)

    def _update_preview(self) -> None:
        name  = self._name_entry.get_text().strip()
        val   = self._val_entry.get_text()
        valid = _valid_env_name(name) if name else False
        self._error_label.set_text('Name must match [A-Za-z_][A-Za-z0-9_]*')
        self._error_label.set_visible(bool(name) and not valid)
        self._preview_label.set_text(f'env = {name},{val}' if name else '')
        self._save_btn.set_sensitive(valid)

    def _on_save_clicked(self, _btn) -> None:
        name = self._name_entry.get_text().strip()
        val  = self._val_entry.get_text()
        if not _valid_env_name(name):
            return
        self._on_save(EnvVar(name=name, value=val))


# ── Shared row helpers ─────────────────────────────────────────────────────────

def _make_list_header(title: str, on_add) -> tuple:
    """Returns (header_box, count_label)."""
    Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_margin_start(16)
    box.set_margin_end(16)
    box.set_margin_top(12)
    box.set_margin_bottom(8)

    lbl = Gtk.Label(label=title)
    lbl.add_css_class('heading')
    lbl.set_xalign(0)
    lbl.set_hexpand(True)

    count = Gtk.Label(label='0')
    count.add_css_class('dim-label')
    count.add_css_class('caption')

    add_btn = Gtk.Button(label='+ Add')
    add_btn.add_css_class('suggested-action')
    add_btn.add_css_class('pill')
    add_btn.connect('clicked', lambda _: on_add())

    box.append(lbl)
    box.append(count)
    box.append(add_btn)
    return box, count


def _make_baseline_row(primary: str, secondary: str, pills: list[str], origin: str, on_edit=None):
    """Read-only list row for entries discovered in distro source files or the
    user file body outside the Cloud-Center-managed sentinel block."""
    Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
    row = Gtk.ListBoxRow()
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    box.set_margin_start(12)
    box.set_margin_end(8)
    box.set_margin_top(8)
    box.set_margin_bottom(8)

    top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    prim_lbl = Gtk.Label(label=primary or '(unnamed)')
    prim_lbl.set_xalign(0)
    prim_lbl.set_hexpand(True)
    prim_lbl.add_css_class('heading')
    prim_lbl.add_css_class('dim-label')
    prim_lbl.set_ellipsize(Pango.EllipsizeMode.END)

    origin_lbl = Gtk.Label(label=origin)
    origin_lbl.add_css_class('caption')
    origin_lbl.add_css_class('tag')
    top.append(prim_lbl)
    top.append(origin_lbl)

    if on_edit is not None:
        edit_btn = Gtk.Button(label='Edit')
        edit_btn.add_css_class('flat')
        edit_btn.connect('clicked', lambda _: on_edit())
        top.append(edit_btn)

    box.append(top)

    if secondary:
        sub = Gtk.Label(label=secondary)
        sub.set_xalign(0)
        sub.add_css_class('dim-label')
        sub.add_css_class('caption')
        sub.set_ellipsize(Pango.EllipsizeMode.END)
        box.append(sub)

    if pills:
        pill_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        pill_box.set_margin_top(2)
        for text in pills:
            p = Gtk.Label(label=text)
            p.add_css_class('caption')
            p.add_css_class('tag')
            pill_box.append(p)
        box.append(pill_box)

    row.set_child(box)
    return row


def _make_rule_row(primary: str, secondary: str, pills: list[str], on_edit, on_delete):
    """Generic list row: primary heading, optional subtitle, pill tags, Edit/Delete buttons."""
    Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
    row = Gtk.ListBoxRow()
    box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    box.set_margin_start(12)
    box.set_margin_end(8)
    box.set_margin_top(8)
    box.set_margin_bottom(8)

    top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    prim_lbl = Gtk.Label(label=primary or '(unnamed)')
    prim_lbl.set_xalign(0)
    prim_lbl.set_hexpand(True)
    prim_lbl.add_css_class('heading')

    edit_btn = Gtk.Button(label='Edit')
    edit_btn.add_css_class('flat')
    edit_btn.connect('clicked', lambda _: on_edit())

    del_btn = Gtk.Button(label='Delete')
    del_btn.add_css_class('flat')
    del_btn.add_css_class('destructive-action')
    del_btn.connect('clicked', lambda _: on_delete())

    top.append(prim_lbl)
    top.append(edit_btn)
    top.append(del_btn)
    box.append(top)

    if secondary:
        sub = Gtk.Label(label=secondary)
        sub.set_xalign(0)
        sub.add_css_class('dim-label')
        sub.add_css_class('caption')
        sub.set_ellipsize(Pango.EllipsizeMode.END)
        box.append(sub)

    if pills:
        pill_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        pill_box.set_margin_top(2)
        for text in pills:
            p = Gtk.Label(label=text)
            p.add_css_class('caption')
            p.add_css_class('tag')
            pill_box.append(p)
        box.append(pill_box)

    row.set_child(box)
    return row


# ── Window Rules Tab ───────────────────────────────────────────────────────────

class _WindowRulesTab(_Gtk.Box):
    def __init__(self, page: 'RulesStartupPage') -> None:
        super().__init__(orientation=_Gtk.Orientation.VERTICAL)
        self._page = page
        self._items:    list[WindowRule] = []
        self._baseline: list[WindowRule] = []
        self._readonly: list[tuple[WindowRule, str]] = []
        self._build_ui()

    def _build_ui(self) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        hdr, self._count_lbl = _make_list_header('Window Rules', self._on_add)
        self.append(hdr)
        self._list = Gtk.ListBox()
        self._list.add_css_class('boxed-list')
        self._list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list.set_margin_start(16)
        self._list.set_margin_end(16)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(self._list)
        self.append(scroll)

    def load(self, items: list[WindowRule]) -> None:
        self._items    = list(items)
        self._baseline = list(items)
        self._refresh()

    def set_readonly(self, items: list[tuple[WindowRule, str]]) -> None:
        self._readonly = list(items)
        self._refresh()

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
        for i, (rule, origin) in enumerate(self._readonly):
            matcher_str = ' · '.join(f'{k} {v}' for k, v in rule.matchers)
            pills = [f'{k}={v}' if v != 'on' else k for k, v in rule.effects.items()]
            self._list.append(_make_baseline_row(
                primary=rule.name or matcher_str,
                secondary=matcher_str if rule.name else '',
                pills=pills,
                origin=origin,
                on_edit=(lambda idx=i: self._on_edit_readonly(idx)) if origin == 'distro' else None,
            ))
        for i, rule in enumerate(self._items):
            matcher_str = ' · '.join(f'{k} {v}' for k, v in rule.matchers)
            pills = [f'{k}={v}' if v != 'on' else k for k, v in rule.effects.items()]
            self._list.append(_make_rule_row(
                primary=rule.name or matcher_str,
                secondary=matcher_str if rule.name else '',
                pills=pills,
                on_edit=lambda idx=i: self._on_edit(idx),
                on_delete=lambda idx=i: self._on_delete(idx),
            ))
        self._count_lbl.set_text(str(len(self._items) + len(self._readonly)))

    def _on_add(self) -> None:
        _WindowRuleDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _WindowRuleDialog(self, lambda r, i=idx: self._mutate_edit(i, r), existing=self._items[idx])

    def _on_edit_readonly(self, idx: int) -> None:
        rule, _origin = self._readonly[idx]

        def on_save(updated: WindowRule) -> None:
            self._readonly.pop(idx)
            self._items.append(updated)
            self._refresh()
            self._page.apply_live()

        _WindowRuleDialog(self, on_save, existing=rule)

    def _on_delete(self, idx: int) -> None:
        self._items.pop(idx)
        self._refresh()
        self._page.apply_live()

    def _mutate_add(self, rule: WindowRule) -> None:
        self._items.append(rule)
        self._refresh()
        self._page.apply_live()

    def _mutate_edit(self, idx: int, rule: WindowRule) -> None:
        self._items[idx] = rule
        self._refresh()
        self._page.apply_live()

    def is_dirty(self) -> bool:        return self._items != self._baseline
    def confirm_baseline(self) -> None: self._baseline = list(self._items)
    def revert_to_baseline(self) -> None:
        self._items = list(self._baseline)
        self._refresh()
    def serialize(self) -> list[str]:   return _serialize_window_rules(self._items)
    def parse(self, lines: list[str]) -> None: self.load(_parse_window_rules(lines))


# ── Layer Rules Tab ────────────────────────────────────────────────────────────

class _LayerRulesTab(_Gtk.Box):
    def __init__(self, page: 'RulesStartupPage') -> None:
        super().__init__(orientation=_Gtk.Orientation.VERTICAL)
        self._page = page
        self._items:    list[LayerRule] = []
        self._baseline: list[LayerRule] = []
        self._readonly: list[tuple[LayerRule, str]] = []
        self._build_ui()

    def _build_ui(self) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        hdr, self._count_lbl = _make_list_header('Layer Rules', self._on_add)
        self.append(hdr)
        self._list = Gtk.ListBox()
        self._list.add_css_class('boxed-list')
        self._list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list.set_margin_start(16)
        self._list.set_margin_end(16)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(self._list)
        self.append(scroll)

    def load(self, items: list[LayerRule]) -> None:
        self._items    = list(items)
        self._baseline = list(items)
        self._refresh()

    def set_readonly(self, items: list[tuple[LayerRule, str]]) -> None:
        self._readonly = list(items)
        self._refresh()

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
        for i, (rule, origin) in enumerate(self._readonly):
            pills = [f'{k}={v}' if v != 'on' else k for k, v in rule.effects.items()]
            self._list.append(_make_baseline_row(
                primary=rule.name or rule.namespace or '(unnamed)',
                secondary=rule.namespace if rule.name else '',
                pills=pills,
                origin=origin,
                on_edit=(lambda idx=i: self._on_edit_readonly(idx)) if origin == 'distro' else None,
            ))
        for i, rule in enumerate(self._items):
            pills = [f'{k}={v}' if v != 'on' else k for k, v in rule.effects.items()]
            self._list.append(_make_rule_row(
                primary=rule.name or rule.namespace or '(unnamed)',
                secondary=rule.namespace if rule.name else '',
                pills=pills,
                on_edit=lambda idx=i: self._on_edit(idx),
                on_delete=lambda idx=i: self._on_delete(idx),
            ))
        self._count_lbl.set_text(str(len(self._items) + len(self._readonly)))

    def _on_add(self) -> None:
        _LayerRuleDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _LayerRuleDialog(self, lambda r, i=idx: self._mutate_edit(i, r), existing=self._items[idx])

    def _on_edit_readonly(self, idx: int) -> None:
        rule, _origin = self._readonly[idx]

        def on_save(updated: LayerRule) -> None:
            self._readonly.pop(idx)
            self._items.append(updated)
            self._refresh()
            self._page.apply_live()

        _LayerRuleDialog(self, on_save, existing=rule)

    def _on_delete(self, idx: int) -> None:
        self._items.pop(idx)
        self._refresh()
        self._page.apply_live()

    def _mutate_add(self, rule: LayerRule) -> None:
        self._items.append(rule)
        self._refresh()
        self._page.apply_live()

    def _mutate_edit(self, idx: int, rule: LayerRule) -> None:
        self._items[idx] = rule
        self._refresh()
        self._page.apply_live()

    def is_dirty(self) -> bool:        return self._items != self._baseline
    def confirm_baseline(self) -> None: self._baseline = list(self._items)
    def revert_to_baseline(self) -> None:
        self._items = list(self._baseline)
        self._refresh()
    def serialize(self) -> list[str]:   return _serialize_layer_rules(self._items)
    def parse(self, lines: list[str]) -> None: self.load(_parse_layer_rules(lines))


# ── Autostart Tab ──────────────────────────────────────────────────────────────

class _AutostartTab(_Gtk.Box):
    def __init__(self, page: 'RulesStartupPage') -> None:
        super().__init__(orientation=_Gtk.Orientation.VERTICAL)
        self._page = page
        self._items:    list[AutostartEntry] = []
        self._baseline: list[AutostartEntry] = []
        self._readonly: list[tuple[AutostartEntry, str]] = []
        self._build_ui()

    def _build_ui(self) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        hdr, self._count_lbl = _make_list_header('Autostart', self._on_add)
        self.append(hdr)
        self._list = Gtk.ListBox()
        self._list.add_css_class('boxed-list')
        self._list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list.set_margin_start(16)
        self._list.set_margin_end(16)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(self._list)
        self.append(scroll)

    def load(self, items: list[AutostartEntry]) -> None:
        self._items    = list(items)
        self._baseline = list(items)
        self._refresh()

    def set_readonly(self, items: list[tuple[AutostartEntry, str]]) -> None:
        self._readonly = list(items)
        self._refresh()

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
        for i, (entry, origin) in enumerate(self._readonly):
            self._list.append(_make_baseline_row(
                primary=entry.command,
                secondary='',
                pills=['exec-once' if entry.exec_once else 'exec'],
                origin=origin,
                on_edit=(lambda idx=i: self._on_edit_readonly(idx)) if origin == 'distro' else None,
            ))
        for i, entry in enumerate(self._items):
            self._list.append(_make_rule_row(
                primary=entry.command,
                secondary='',
                pills=['exec-once' if entry.exec_once else 'exec'],
                on_edit=lambda idx=i: self._on_edit(idx),
                on_delete=lambda idx=i: self._on_delete(idx),
            ))
        self._count_lbl.set_text(str(len(self._items) + len(self._readonly)))

    def _on_add(self) -> None:
        _AutostartDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _AutostartDialog(self, lambda e, i=idx: self._mutate_edit(i, e), existing=self._items[idx])

    def _on_edit_readonly(self, idx: int) -> None:
        entry, _origin = self._readonly[idx]

        def on_save(updated: AutostartEntry) -> None:
            self._readonly.pop(idx)
            self._items.append(updated)
            self._refresh()
            self._page.apply_live()

        _AutostartDialog(self, on_save, existing=entry)

    def _on_delete(self, idx: int) -> None:
        self._items.pop(idx)
        self._refresh()
        self._page.apply_live()

    def _mutate_add(self, entry: AutostartEntry) -> None:
        self._items.append(entry)
        self._refresh()
        self._page.apply_live()

    def _mutate_edit(self, idx: int, entry: AutostartEntry) -> None:
        self._items[idx] = entry
        self._refresh()
        self._page.apply_live()

    def is_dirty(self) -> bool:        return self._items != self._baseline
    def confirm_baseline(self) -> None: self._baseline = list(self._items)
    def revert_to_baseline(self) -> None:
        self._items = list(self._baseline)
        self._refresh()
    def serialize(self) -> list[str]:   return _serialize_autostart(self._items)
    def parse(self, lines: list[str]) -> None: self.load(_parse_autostart(lines))


# ── Env Vars Tab ───────────────────────────────────────────────────────────────

class _EnvVarsTab(_Gtk.Box):
    def __init__(self, page: 'RulesStartupPage') -> None:
        super().__init__(orientation=_Gtk.Orientation.VERTICAL)
        self._page = page
        self._items:    list[EnvVar] = []
        self._baseline: list[EnvVar] = []
        self._readonly: list[tuple[EnvVar, str]] = []
        self._build_ui()

    def _build_ui(self) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        hdr, self._count_lbl = _make_list_header('Environment Variables', self._on_add)
        self.append(hdr)
        self._list = Gtk.ListBox()
        self._list.add_css_class('boxed-list')
        self._list.set_selection_mode(Gtk.SelectionMode.NONE)
        self._list.set_margin_start(16)
        self._list.set_margin_end(16)
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(self._list)
        self.append(scroll)

    def load(self, items: list[EnvVar]) -> None:
        self._items    = list(items)
        self._baseline = list(items)
        self._refresh()

    def set_readonly(self, items: list[tuple[EnvVar, str]]) -> None:
        self._readonly = list(items)
        self._refresh()

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
        for i, (var, origin) in enumerate(self._readonly):
            self._list.append(_make_baseline_row(
                primary=var.name,
                secondary=var.value,
                pills=[],
                origin=origin,
                on_edit=(lambda idx=i: self._on_edit_readonly(idx)) if origin == 'distro' else None,
            ))
        for i, var in enumerate(self._items):
            self._list.append(_make_rule_row(
                primary=var.name,
                secondary=var.value,
                pills=[],
                on_edit=lambda idx=i: self._on_edit(idx),
                on_delete=lambda idx=i: self._on_delete(idx),
            ))
        self._count_lbl.set_text(str(len(self._items) + len(self._readonly)))

    def _on_add(self) -> None:
        _EnvVarDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _EnvVarDialog(self, lambda v, i=idx: self._mutate_edit(i, v), existing=self._items[idx])

    def _on_edit_readonly(self, idx: int) -> None:
        var, _origin = self._readonly[idx]

        def on_save(updated: EnvVar) -> None:
            self._readonly.pop(idx)
            self._items.append(updated)
            self._refresh()
            self._page.apply_live()

        _EnvVarDialog(self, on_save, existing=var)

    def _on_delete(self, idx: int) -> None:
        self._items.pop(idx)
        self._refresh()
        self._page.apply_live()

    def _mutate_add(self, var: EnvVar) -> None:
        self._items.append(var)
        self._refresh()
        self._page.apply_live()

    def _mutate_edit(self, idx: int, var: EnvVar) -> None:
        self._items[idx] = var
        self._refresh()
        self._page.apply_live()

    def is_dirty(self) -> bool:        return self._items != self._baseline
    def confirm_baseline(self) -> None: self._baseline = list(self._items)
    def revert_to_baseline(self) -> None:
        self._items = list(self._baseline)
        self._refresh()
    def serialize(self) -> list[str]:   return _serialize_env_vars(self._items)
    def parse(self, lines: list[str]) -> None: self.load(_parse_env_vars(lines))


# ── Rules & Startup Page ───────────────────────────────────────────────────────

class RulesStartupPage(_Gtk.Box):
    """Tabbed page: Window Rules, Layer Rules, Autostart, Environment Variables."""

    def __init__(self, toast_overlay) -> None:
        super().__init__(orientation=_Gtk.Orientation.VERTICAL)
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._toast_ov = toast_overlay

        self._window_tab    = _WindowRulesTab(self)
        self._layer_tab     = _LayerRulesTab(self)
        self._autostart_tab = _AutostartTab(self)
        self._env_tab       = _EnvVarsTab(self)
        self._tabs = [self._window_tab, self._layer_tab, self._autostart_tab, self._env_tab]

        stack = Adw.ViewStack()
        stack.add_titled(self._window_tab,    'window',    'Window Rules')
        stack.add_titled(self._layer_tab,     'layer',     'Layer Rules')
        stack.add_titled(self._autostart_tab, 'autostart', 'Autostart')
        stack.add_titled(self._env_tab,       'env',       'Environment')
        stack.set_vexpand(True)

        switcher = Adw.ViewSwitcher()
        switcher.set_stack(stack)
        switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)

        header = Adw.HeaderBar()
        header.set_title_widget(switcher)
        header.add_css_class('flat')

        toolbar_view = Adw.ToolbarView()
        toolbar_view.add_top_bar(header)
        toolbar_view.set_content(stack)
        toolbar_view.add_bottom_bar(self._build_footer())
        toolbar_view.set_vexpand(True)
        self.append(toolbar_view)

        self._load_from_files()

    def _build_footer(self):
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.add_css_class('toolbar')
        box.set_margin_start(6)
        box.set_margin_end(6)

        path_lbl = Gtk.Label(label='~/.config/hypr/{windowrules,autostart,variables}.lua')
        path_lbl.add_css_class('dim-label')
        path_lbl.add_css_class('caption')
        path_lbl.set_hexpand(True)
        path_lbl.set_xalign(0)
        path_lbl.set_ellipsize(Pango.EllipsizeMode.END)

        self._discard_btn = Gtk.Button(label='Discard')
        self._discard_btn.add_css_class('flat')
        self._discard_btn.set_sensitive(False)
        self._discard_btn.connect('clicked', self._on_discard)

        self._apply_btn = Gtk.Button(label='Apply')
        self._apply_btn.add_css_class('suggested-action')
        self._apply_btn.set_sensitive(False)
        self._apply_btn.connect('clicked', self._on_apply)

        box.append(path_lbl)
        box.append(self._discard_btn)
        box.append(self._apply_btn)
        return box

    def _load_from_files(self) -> None:
        user_texts = {
            surface: path.read_text(encoding='utf-8') if path.exists() else ''
            for surface, path in SURFACE_PATHS.items()
        }
        try:
            window_sections = _parse_conf(user_texts['windowrules'])
            autostart_sections = _parse_conf(user_texts['autostart'])
            variable_sections = _parse_conf(user_texts['variables'])
            self._window_tab.parse(window_sections['window_rules'])
            self._layer_tab.parse(window_sections['layer_rules'])
            self._autostart_tab.parse(autostart_sections['autostart'])
            self._env_tab.parse(variable_sections['env_vars'])
        except Exception as e:
            log.warning('Failed to load split Rules & Startup configs: %s', e)

        # Distro baselines and hand-written additions are visible but locked.
        # Managed blocks are replaced in place, so those manual additions are
        # preserved byte-for-byte on every subsequent Cloud Center edit.  The
        # "distro" reference is the shipped seed each surface was created
        # from (install/default-theme/hypr/<surface>.lua) — there's no
        # separate runtime source file anymore; every module is one live,
        # edited-in-place file.
        try:
            distro_window_path = hcm_lua.DEFAULTS_DIR / 'windowrules.lua'
            distro_autostart_path = hcm_lua.DEFAULTS_DIR / 'autostart.lua'
            distro_variable_path = hcm_lua.DEFAULTS_DIR / 'variables.lua'
            distro_window_text = distro_window_path.read_text(encoding='utf-8') if distro_window_path.exists() else ''
            distro_autostart_text = distro_autostart_path.read_text(encoding='utf-8') if distro_autostart_path.exists() else ''
            distro_variable_text = distro_variable_path.read_text(encoding='utf-8') if distro_variable_path.exists() else ''

            distro_windows = _dataclass_window_rules(distro_window_text)
            distro_layers = _dataclass_layer_rules(distro_window_text)
            distro_autostart = _dataclass_autostart(distro_autostart_text)
            distro_env = _dataclass_env_vars(distro_variable_text)

            sentinel_windows  = list(self._window_tab._items)
            sentinel_layers   = list(self._layer_tab._items)
            sentinel_autostart = list(self._autostart_tab._items)
            sentinel_env      = list(self._env_tab._items)

            body_windows = [
                WindowRule(**w) for w in hyprlua_reader.parse_window_rules(user_texts['windowrules'])
                if WindowRule(**w) not in sentinel_windows
                and WindowRule(**w) not in distro_windows
            ]
            body_layers = [
                LayerRule(**l) for l in hyprlua_reader.parse_layer_rules(user_texts['windowrules'])
                if LayerRule(**l) not in sentinel_layers
                and LayerRule(**l) not in distro_layers
            ]
            body_autostart = [
                AutostartEntry(**a) for a in hyprlua_reader.parse_autostart(user_texts['autostart'])
                if AutostartEntry(**a) not in sentinel_autostart
                and AutostartEntry(**a) not in distro_autostart
            ]
            body_env = [
                EnvVar(**e) for e in hyprlua_reader.parse_env_vars(user_texts['variables'])
                if EnvVar(**e) not in sentinel_env
                and EnvVar(**e) not in distro_env
            ]

            self._window_tab.set_readonly(
                [(r, 'distro') for r in distro_windows]
                + [(r, 'user-manual') for r in body_windows]
            )
            self._layer_tab.set_readonly(
                [(r, 'distro') for r in distro_layers]
                + [(r, 'user-manual') for r in body_layers]
            )
            self._autostart_tab.set_readonly(
                [(r, 'distro') for r in distro_autostart]
                + [(r, 'user-manual') for r in body_autostart]
            )
            self._env_tab.set_readonly(
                [(r, 'distro') for r in distro_env]
                + [(r, 'user-manual') for r in body_env]
            )
        except Exception as e:
            log.warning('Failed to load read-only baseline: %s', e)

    def _dirty_surfaces(self) -> set[str]:
        surfaces: set[str] = set()
        if self._window_tab.is_dirty() or self._layer_tab.is_dirty():
            surfaces.add('windowrules')
        if self._autostart_tab.is_dirty():
            surfaces.add('autostart')
        if self._env_tab.is_dirty():
            surfaces.add('variables')
        return surfaces

    def apply_live(self, surfaces: set[str] | None = None) -> None:
        """Write only dirty surfaces + reload after a tab mutation."""
        self._update_dirty_buttons()
        selected = self._dirty_surfaces() if surfaces is None else set(surfaces)
        if not selected:
            return
        snapshot = (
            deepcopy(self._window_tab._items),
            deepcopy(self._layer_tab._items),
            deepcopy(self._autostart_tab._items),
            deepcopy(self._env_tab._items),
        )
        threading.Thread(
            target=self._do_apply_live,
            args=(*snapshot, selected),
            daemon=True,
        ).start()

    def _do_apply_live(
        self,
        window_rules: list[WindowRule],
        layer_rules: list[LayerRule],
        autostart: list[AutostartEntry],
        env_vars: list[EnvVar],
        surfaces: set[str],
    ) -> None:
        from gi.repository import GLib
        try:
            _write_conf(
                window_rules,
                layer_rules,
                autostart,
                env_vars,
                surfaces=surfaces,
            )
            subprocess.run(['hyprctl', 'reload'], capture_output=True, timeout=5)
        except Exception as e:
            GLib.idle_add(lambda msg=str(e): self._show_toast(f'Reload failed: {msg}'))

    def _update_dirty_buttons(self) -> None:
        dirty = any(t.is_dirty() for t in self._tabs)
        self._discard_btn.set_sensitive(dirty)
        self._apply_btn.set_sensitive(dirty)

    def _on_apply(self, _btn) -> None:
        for tab in self._tabs:
            tab.confirm_baseline()
        self._update_dirty_buttons()
        has_startup = bool(self._autostart_tab._items) or bool(self._env_tab._items)
        msg = 'Saved — restart Hyprland for env & autostart changes' if has_startup else 'Rules saved'
        self._show_toast(msg)

    def _on_discard(self, _btn) -> None:
        dirty_surfaces = self._dirty_surfaces()
        for tab in self._tabs:
            tab.revert_to_baseline()
        self.apply_live(dirty_surfaces)

    def _show_toast(self, msg: str) -> None:
        from lib import utility
        utility.toast(self._toast_ov, msg)
