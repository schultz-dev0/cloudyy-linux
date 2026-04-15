"""
waybar-editor/panels/modules.py
Left panel: module list grouped by position with toggle + reorder controls.
"""
from __future__ import annotations

import logging
from typing import Callable

from gi.repository import Adw, Gtk

log = logging.getLogger(__name__)

from models import Position, Preset, WaybarModule


class ModulesPanel(Gtk.Box):
    """
    Left panel showing modules grouped into LEFT / CENTER / RIGHT.
    Each row: toggle switch, display name, up/down buttons.
    Emits on_change() whenever the module list is mutated.
    """

    def __init__(self, on_change: Callable[[], None]) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._on_change = on_change
        self._preset: Preset | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        header = Gtk.Label(label="Modules")
        header.add_css_class("heading")
        header.set_xalign(0)
        header.set_margin_start(12)
        header.set_margin_top(12)
        header.set_margin_bottom(6)
        self.append(header)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        self._inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._inner.set_margin_start(8)
        self._inner.set_margin_end(8)
        self._inner.set_margin_bottom(8)
        scroll.set_child(self._inner)
        self.append(scroll)

    def load_preset(self, preset: Preset) -> None:
        self._preset = preset
        self._rebuild()

    def _rebuild(self) -> None:
        # Clear existing children
        while child := self._inner.get_first_child():
            self._inner.remove(child)

        if self._preset is None:
            return

        for position, modules, label in [
            (Position.LEFT,   self._preset.modules_left,   "Left"),
            (Position.CENTER, self._preset.modules_center, "Center"),
            (Position.RIGHT,  self._preset.modules_right,  "Right"),
        ]:
            group = self._build_group(label, modules)
            self._inner.append(group)

    def _build_group(self, label: str, modules: list[WaybarModule]) -> Gtk.Widget:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_top(8)

        lbl = Gtk.Label(label=label)
        lbl.add_css_class("caption-heading")
        lbl.add_css_class("dim-label")
        lbl.set_xalign(0)
        lbl.set_margin_start(4)
        lbl.set_margin_bottom(2)
        box.append(lbl)

        frame = Gtk.ListBox()
        frame.add_css_class("boxed-list")
        frame.set_selection_mode(Gtk.SelectionMode.NONE)

        for i, mod in enumerate(modules):
            frame.append(self._build_module_row(mod, modules, i))

        box.append(frame)
        return box

    def _build_module_row(
        self, mod: WaybarModule, group: list[WaybarModule], idx: int
    ) -> Gtk.ListBoxRow:
        row = Adw.ActionRow(title=mod.display_name)
        row.set_subtitle(mod.name)

        # Toggle
        toggle = Gtk.Switch()
        toggle.set_active(mod.enabled)
        toggle.set_valign(Gtk.Align.CENTER)
        toggle.connect("state-set", self._on_toggle, mod)
        row.add_suffix(toggle)
        row.set_activatable_widget(toggle)

        # Up / Down buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        btn_box.set_valign(Gtk.Align.CENTER)

        up_btn = Gtk.Button.new_from_icon_name("go-up-symbolic")
        up_btn.add_css_class("flat")
        up_btn.set_sensitive(idx > 0)
        up_btn.set_tooltip_text("Move up")
        up_btn.connect("clicked", self._on_move, group, idx, -1)

        dn_btn = Gtk.Button.new_from_icon_name("go-down-symbolic")
        dn_btn.add_css_class("flat")
        dn_btn.set_sensitive(idx < len(group) - 1)
        dn_btn.set_tooltip_text("Move down")
        dn_btn.connect("clicked", self._on_move, group, idx, +1)

        btn_box.append(up_btn)
        btn_box.append(dn_btn)
        row.add_suffix(btn_box)

        return row

    def _on_toggle(self, switch: Gtk.Switch, state: bool, mod: WaybarModule) -> bool:
        mod.enabled = state
        self._on_change()
        return False  # allow switch to update visually

    def _on_move(
        self, _btn: Gtk.Button,
        group: list[WaybarModule], idx: int, direction: int
    ) -> None:
        target = idx + direction
        if 0 <= target < len(group):
            group[idx], group[target] = group[target], group[idx]
            self._rebuild()
            self._on_change()
