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


# ── GTK import helper ──────────────────────────────────────────────────────────
# Deferred so parse/serialize tests can import this module without a display.

def _gtk_imports():
    from gi.repository import Adw, Gdk, GLib, Gtk, Pango
    return Adw, Gdk, GLib, Gtk, Pango


# ── Window Picker Dialog ───────────────────────────────────────────────────────

class _WindowPickerDialog:
    """Lists running Hyprland windows; calls on_pick(window_class) on select."""

    def __init__(self, parent_widget, on_pick) -> None:
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        self._on_pick = on_pick

        self._dialog = Adw.Dialog()
        self._dialog.set_title('Pick a Window')
        self._dialog.set_content_width(400)
        self._dialog.set_content_height(400)

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
        self._dialog.present(parent_widget)
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
    'match:xwayland', 'match:floating', 'match:fullscreen',
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
        self._dialog.set_content_width(480)

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
        self._dialog.present(parent_widget)

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
