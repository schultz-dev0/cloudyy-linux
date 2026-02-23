"""
Cloud Center — lib/rows.py
Native GTK4/Libadwaita row widgets driven by config.yaml.
Supports both GTK symbolic icon names and Nerd Font glyph characters.
"""
from __future__ import annotations

import logging
import threading
from typing import Any

from gi.repository import Adw, GLib, Gtk

import lib.utility as utility

log = logging.getLogger(__name__)


# ── Nerd Font / icon helper ───────────────────────────────────────────────────

def _make_prefix_icon(icon_name: str) -> Gtk.Widget:
    """
    Return a Gtk.Image for GTK symbolic icon names, or a Gtk.Label for
    Nerd Font glyphs (detected by the presence of any non-ASCII codepoint).
    """
    if not icon_name:
        return Gtk.Box()
    if any(ord(c) > 127 for c in icon_name):
        lbl = Gtk.Label(label=icon_name)
        lbl.add_css_class("nerd-icon")
        lbl.add_css_class("row-nerd-icon")
        return lbl
    return Gtk.Image.new_from_icon_name(icon_name)


# ── Shared context passed to every row ───────────────────────────────────────

class RowContext:
    def __init__(self, toast_overlay: Adw.ToastOverlay):
        self.toast_overlay = toast_overlay

    def toast(self, msg: str) -> None:
        utility.toast(self.toast_overlay, msg)


# ── Base widget lifecycle helper ──────────────────────────────────────────────

class _ManagedRow:
    """Mixin that tracks GLib source IDs and cancels them on unroot."""

    def _init_sources(self) -> None:
        self._sources: list[int] = []
        self._destroyed = False
        self._lock = threading.Lock()

    def _add_source(self, sid: int) -> None:
        with self._lock:
            if not self._destroyed:
                self._sources.append(sid)

    def _cleanup(self) -> None:
        with self._lock:
            self._destroyed = True
            sources, self._sources = self._sources, []
        for sid in sources:
            GLib.source_remove(sid)


# ── Button row ────────────────────────────────────────────────────────────────

class ButtonRow(Adw.ActionRow, _ManagedRow):
    __gtype_name__ = "CCButtonRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))
        self.set_activatable(True)

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        btn_label = props.get("button_text", "")
        if btn_label:
            btn = Gtk.Button(label=btn_label, valign=Gtk.Align.CENTER)
            btn.add_css_class("flat")
            btn.connect("clicked", self._on_activate)
            self.add_suffix(btn)
        else:
            chevron = Gtk.Image.new_from_icon_name("go-next-symbolic")
            self.add_suffix(chevron)

        self.connect("activated", self._on_activate)

    def _on_activate(self, *_) -> None:
        cmd = self._action.get("command", "")
        terminal = bool(self._action.get("terminal", False))
        if cmd:
            ok = utility.execute_command(cmd, terminal=terminal)
            self._ctx.toast(" Launched" if ok else " Failed")

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ActionRow.do_unroot(self)


# ── Toggle row ────────────────────────────────────────────────────────────────

class ToggleRow(Adw.ActionRow, _ManagedRow):
    __gtype_name__ = "CCToggleRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx
        self._key = props.get("key", "")
        self._state_cmd = props.get("state_command", "")
        self._interval = int(props.get("interval", 5))

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        self._switch = Gtk.Switch(valign=Gtk.Align.CENTER)
        self.add_suffix(self._switch)
        self.set_activatable_widget(self._switch)

        # Load persisted state
        if self._key:
            self._switch.set_active(utility.load_setting(self._key, False))

        self._switch.connect("state-set", self._on_toggle)

        # Poll state_command if defined
        if self._state_cmd:
            self._poll_state()
            sid = GLib.timeout_add_seconds(self._interval, self._poll_state)
            self._add_source(sid)

    def _poll_state(self) -> bool:
        with self._lock:
            if self._destroyed:
                return GLib.SOURCE_REMOVE
        threading.Thread(target=self._fetch_state, daemon=True).start()
        return GLib.SOURCE_CONTINUE

    def _fetch_state(self) -> None:
        import subprocess
        try:
            r = subprocess.run(
                ["bash", "-c", self._state_cmd],
                capture_output=True, text=True, timeout=5
            )
            out = r.stdout.strip().lower()
            active = (
                out in {"yes", "true", "1", "on", "enabled", "active", "running"}
                or (out.isdigit() and int(out) > 0)
            )
            GLib.idle_add(self._apply_state, active)
        except Exception:
            pass

    def _apply_state(self, active: bool) -> bool:
        with self._lock:
            if self._destroyed:
                return GLib.SOURCE_REMOVE
        self._switch.handler_block_by_func(self._on_toggle)
        self._switch.set_active(active)
        self._switch.handler_unblock_by_func(self._on_toggle)
        return GLib.SOURCE_REMOVE

    def _on_toggle(self, switch: Gtk.Switch, state: bool) -> bool:
        key = "enabled" if state else "disabled"
        act = self._action.get(key, {})
        if cmd := act.get("command", ""):
            utility.execute_command(cmd, terminal=bool(act.get("terminal", False)))
        if self._key:
            threading.Thread(
                target=utility.save_setting, args=(self._key, state), daemon=True
            ).start()
        return False  # allow default visual update

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ActionRow.do_unroot(self)


# ── Slider row ────────────────────────────────────────────────────────────────

class SliderRow(Adw.ActionRow, _ManagedRow):
    __gtype_name__ = "CCSliderRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx
        self._key = props.get("key", "")
        self._debounce_sid: int = 0
        self._cmd_template: str = action.get("command", "") if action else ""

        mn   = float(props.get("min",  0))
        mx   = float(props.get("max",  100))
        step = float(props.get("step", 1))
        default = float(props.get("default", mn))

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, mn, mx, step)
        scale.set_hexpand(True)
        scale.set_size_request(160, -1)
        scale.set_draw_value(True)
        scale.set_valign(Gtk.Align.CENTER)

        if self._key:
            scale.set_value(utility.load_setting(self._key, default))
        else:
            scale.set_value(default)

        scale.connect("value-changed", self._on_change)
        self.add_suffix(scale)
        self._scale = scale

    def _on_change(self, scale: Gtk.Scale) -> None:
        if self._debounce_sid:
            GLib.source_remove(self._debounce_sid)
        self._debounce_sid = GLib.timeout_add(150, self._apply, scale.get_value())

    def _apply(self, value: float) -> bool:
        self._debounce_sid = 0
        if self._key:
            threading.Thread(
                target=utility.save_setting, args=(self._key, value), daemon=True
            ).start()
        if self._cmd_template:
            cmd = self._cmd_template.replace("{value}", str(int(value))).replace("{value_f}", f"{value:.2f}")
            utility.execute_command(cmd)
        return GLib.SOURCE_REMOVE

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ActionRow.do_unroot(self)


# ── Selection (combo) row ─────────────────────────────────────────────────────

class SelectionRow(Adw.ComboRow, _ManagedRow):
    __gtype_name__ = "CCSelectionRow"

    def __init__(self, props: dict, action: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._action = action or {}
        self._ctx = ctx
        self._key = props.get("key", "")
        self._options = props.get("options", [])
        self._options_map = props.get("options_map", {})
        self._cmd_template: str = action.get("command", "") if action else ""

        self.set_title(props.get("title", ""))
        self.set_subtitle(props.get("description", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        store = Gtk.StringList.new(self._options)
        self.set_model(store)

        saved = utility.load_setting(self._key, "") if self._key else ""
        if saved in self._options:
            self.set_selected(self._options.index(saved))

        self.connect("notify::selected", self._on_change)

    def _on_change(self, *_) -> None:
        idx = self.get_selected()
        if idx >= len(self._options):
            return
        value = self._options[idx]
        mapped = self._options_map.get(value, value)

        if self._key:
            threading.Thread(
                target=utility.save_setting, args=(self._key, value), daemon=True
            ).start()

        if self._cmd_template:
            cmd = self._cmd_template.replace("{value}", mapped).replace("{option}", value)
            utility.execute_command(cmd)

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ComboRow.do_unroot(self)


# ── Label (info display) row ──────────────────────────────────────────────────

class LabelRow(Adw.ActionRow, _ManagedRow):
    __gtype_name__ = "CCLabelRow"

    def __init__(self, props: dict, value_cfg: dict | None, ctx: RowContext) -> None:
        super().__init__()
        self._init_sources()
        self._ctx = ctx
        self._value_cfg = value_cfg or {}

        self.set_title(props.get("title", ""))

        if icon := props.get("icon"):
            self.add_prefix(_make_prefix_icon(icon))

        self._label = Gtk.Label(label="…", valign=Gtk.Align.CENTER)
        self._label.add_css_class("dim-label")
        self.add_suffix(self._label)

        self._refresh()
        interval = int(props.get("interval", 0))
        if interval > 0:
            sid = GLib.timeout_add_seconds(interval, self._refresh)
            self._add_source(sid)

    def _refresh(self) -> bool:
        vtype = self._value_cfg.get("type", "")
        match vtype:
            case "system":
                val = utility.get_system_info(self._value_cfg.get("key", ""))
                self._label.set_label(val)
            case "exec":
                cmd = self._value_cfg.get("command", "")
                threading.Thread(target=self._exec_value, args=(cmd,), daemon=True).start()
            case "static":
                self._label.set_label(str(self._value_cfg.get("text", "")))
        return GLib.SOURCE_CONTINUE

    def _exec_value(self, cmd: str) -> None:
        import subprocess
        try:
            r = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=5)
            val = r.stdout.strip() or "N/A"
        except Exception:
            val = "Error"
        GLib.idle_add(self._label.set_label, val)

    def do_unroot(self) -> None:
        self._cleanup()
        Adw.ActionRow.do_unroot(self)


# ── Row factory ───────────────────────────────────────────────────────────────

def build_row(item: dict, ctx: RowContext) -> Gtk.Widget | None:
    itype = item.get("type", "")
    props = item.get("properties", {})
    try:
        match itype:
            case "button":
                return ButtonRow(props, item.get("on_press"), ctx)
            case "toggle":
                return ToggleRow(props, item.get("on_toggle"), ctx)
            case "slider":
                return SliderRow(props, item.get("on_change"), ctx)
            case "selection":
                return SelectionRow(props, item.get("on_change"), ctx)
            case "label":
                return LabelRow(props, item.get("value"), ctx)
            case _:
                log.warning("Unknown row type: %s", itype)
                return None
    except Exception as e:
        log.error("Failed to build row type=%s: %s", itype, e)
        err = Adw.ActionRow(title=f" {props.get('title','?')}", subtitle=str(e)[:80])
        err.add_css_class("error")
        return err