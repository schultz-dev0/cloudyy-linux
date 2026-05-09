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

from gi.repository import Gtk as _Gtk

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
        self._dialog.set_content_width(440)

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
        self._dialog.present(parent_widget)

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
        self._dialog.set_content_width(400)
        self._dialog.set_content_height(460)

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
        self._dialog.present(parent_widget)
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
        self._dialog.set_content_width(440)

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

        self._dialog.present(parent_widget)

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
        self._dialog.set_content_width(400)

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
        self._dialog.present(parent_widget)

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

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
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
        self._count_lbl.set_text(str(len(self._items)))

    def _on_add(self) -> None:
        _WindowRuleDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _WindowRuleDialog(self, lambda r, i=idx: self._mutate_edit(i, r), existing=self._items[idx])

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

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
        for i, rule in enumerate(self._items):
            pills = [f'{k}={v}' if v != 'on' else k for k, v in rule.effects.items()]
            self._list.append(_make_rule_row(
                primary=rule.name or rule.namespace or '(unnamed)',
                secondary=rule.namespace if rule.name else '',
                pills=pills,
                on_edit=lambda idx=i: self._on_edit(idx),
                on_delete=lambda idx=i: self._on_delete(idx),
            ))
        self._count_lbl.set_text(str(len(self._items)))

    def _on_add(self) -> None:
        _LayerRuleDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _LayerRuleDialog(self, lambda r, i=idx: self._mutate_edit(i, r), existing=self._items[idx])

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

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
        for i, entry in enumerate(self._items):
            self._list.append(_make_rule_row(
                primary=entry.command,
                secondary='',
                pills=['exec-once' if entry.exec_once else 'exec'],
                on_edit=lambda idx=i: self._on_edit(idx),
                on_delete=lambda idx=i: self._on_delete(idx),
            ))
        self._count_lbl.set_text(str(len(self._items)))

    def _on_add(self) -> None:
        _AutostartDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _AutostartDialog(self, lambda e, i=idx: self._mutate_edit(i, e), existing=self._items[idx])

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

    def _refresh(self) -> None:
        while child := self._list.get_row_at_index(0):
            self._list.remove(child)
        for i, var in enumerate(self._items):
            self._list.append(_make_rule_row(
                primary=var.name,
                secondary=var.value,
                pills=[],
                on_edit=lambda idx=i: self._on_edit(idx),
                on_delete=lambda idx=i: self._on_delete(idx),
            ))
        self._count_lbl.set_text(str(len(self._items)))

    def _on_add(self) -> None:
        _EnvVarDialog(self, self._mutate_add)

    def _on_edit(self, idx: int) -> None:
        _EnvVarDialog(self, lambda v, i=idx: self._mutate_edit(i, v), existing=self._items[idx])

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

        self._load_from_file()

    def _build_footer(self):
        Adw, Gdk, GLib, Gtk, Pango = _gtk_imports()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.add_css_class('toolbar')
        box.set_margin_start(6)
        box.set_margin_end(6)

        path_lbl = Gtk.Label(label=str(CONF_PATH).replace(str(Path.home()), '~'))
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

    def _load_from_file(self) -> None:
        if not CONF_PATH.exists():
            return
        try:
            sections = _parse_conf(CONF_PATH.read_text(encoding='utf-8'))
            self._window_tab.parse(sections['window_rules'])
            self._layer_tab.parse(sections['layer_rules'])
            self._autostart_tab.parse(sections['autostart'])
            self._env_tab.parse(sections['env_vars'])
        except Exception as e:
            log.warning('Failed to load rules conf: %s', e)

    def apply_live(self) -> None:
        """Write conf + reload. Called by tabs after any mutation."""
        self._update_dirty_buttons()
        threading.Thread(target=self._do_apply_live, daemon=True).start()

    def _do_apply_live(self) -> None:
        from gi.repository import GLib
        try:
            _write_conf(
                self._window_tab._items,
                self._layer_tab._items,
                self._autostart_tab._items,
                self._env_tab._items,
            )
            subprocess.run(['hyprctl', 'reload'], capture_output=True, timeout=5)
        except Exception as e:
            GLib.idle_add(lambda msg=str(e): self._show_toast(f'Reload failed: {msg}'))

    def _update_dirty_buttons(self) -> None:
        dirty = any(t.is_dirty() for t in self._tabs)
        self._discard_btn.set_sensitive(dirty)
        self._apply_btn.set_sensitive(dirty)

    def _on_apply(self, _btn) -> None:
        import lib.hcm as hcm
        for tab in self._tabs:
            tab.confirm_baseline()
        hcm.ensure_user_config_sourced(CONF_PATH)
        self._update_dirty_buttons()
        has_startup = bool(self._autostart_tab._items) or bool(self._env_tab._items)
        msg = 'Saved — restart Hyprland for env & autostart changes' if has_startup else 'Rules saved'
        self._show_toast(msg)

    def _on_discard(self, _btn) -> None:
        for tab in self._tabs:
            tab.revert_to_baseline()
        self.apply_live()

    def _show_toast(self, msg: str) -> None:
        from lib import utility
        utility.toast(self._toast_ov, msg)
