"""
waybar-editor/panels/properties.py
Center panel: Colors tab, Spacing tab, Raw CSS tab.
"""
from __future__ import annotations

import json
import logging
import re
from typing import Callable

from gi.repository import Adw, Gdk, GLib, Gtk

from models import CSSVar, Preset
from parser import parse_css, parse_config, strip_jsonc
from writer import update_css_property, update_css_var

log = logging.getLogger(__name__)


# ── Spacing properties we expose as sliders ───────────────────────────────────

SPACING_PROPS = [
    ("#waybar",          "padding",         "Bar Padding",          0, 40),
    ("#waybar",          "font-size",        "Bar Font Size (px)",   8, 32),
    ("window#waybar",    "border-radius",    "Bar Corner Radius",    0, 30),
    ("#workspaces button","padding",         "Workspace Padding",    0, 24),
    ("#workspaces button","border-radius",   "Workspace Radius",     0, 20),
    ("#clock",           "padding",          "Clock Padding",        0, 24),
    ("#clock",           "border-radius",    "Clock Radius",         0, 20),
    ("tooltip",          "border-radius",    "Tooltip Radius",       0, 20),
]


def _parse_px(value: str) -> int:
    """Extract first integer from a CSS value string."""
    m = re.search(r"(\d+)", value)
    return int(m.group(1)) if m else 0


def _rgba_to_hex(rgba: Gdk.RGBA) -> str:
    r = int(rgba.red   * 255)
    g = int(rgba.green * 255)
    b = int(rgba.blue  * 255)
    a = rgba.alpha
    if a < 1.0:
        return f"rgba({r},{g},{b},{a:.2f})"
    return f"#{r:02x}{g:02x}{b:02x}"


def _hex_to_rgba(value: str) -> Gdk.RGBA:
    rgba = Gdk.RGBA()
    if not rgba.parse(value):
        rgba.parse("rgba(127,127,127,1)")
    return rgba


class PropertiesPanel(Gtk.Box):
    """
    Three-tab panel:
      Colors   — @define-color variables as color buttons
      Spacing  — known selector properties as sliders
      Raw CSS  — full editable text view
    """

    def __init__(
        self,
        on_change: Callable[[], None],
        on_module_config_parsed: Callable[["Preset"], None] | None = None,
    ) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._on_change               = on_change
        self._on_module_config_parsed = on_module_config_parsed
        self._preset: Preset | None   = None
        self._raw_debounce: int       = 0
        self._cfg_debounce: int       = 0
        self._build_ui()

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        self._stack = Adw.ViewStack()
        self._stack.set_vexpand(True)

        # Colors tab
        self._colors_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        colors_scroll = Gtk.ScrolledWindow()
        colors_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        colors_scroll.set_vexpand(True)
        self._colors_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._colors_inner.set_margin_start(12)
        self._colors_inner.set_margin_end(12)
        self._colors_inner.set_margin_top(12)
        self._colors_inner.set_margin_bottom(12)
        colors_scroll.set_child(self._colors_inner)
        self._colors_box.append(colors_scroll)

        colors_page = self._stack.add_titled(self._colors_box, "colors", "Colors")
        colors_page.set_icon_name("color-select-symbolic")

        # Spacing tab
        self._spacing_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        spacing_scroll = Gtk.ScrolledWindow()
        spacing_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        spacing_scroll.set_vexpand(True)
        self._spacing_inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._spacing_inner.set_margin_start(12)
        self._spacing_inner.set_margin_end(12)
        self._spacing_inner.set_margin_top(12)
        self._spacing_inner.set_margin_bottom(12)
        spacing_scroll.set_child(self._spacing_inner)
        self._spacing_box.append(spacing_scroll)

        spacing_page = self._stack.add_titled(self._spacing_box, "spacing", "Spacing")
        spacing_page.set_icon_name("preferences-other-symbolic")

        # Raw CSS tab
        self._raw_buf = Gtk.TextBuffer()
        self._raw_buf.connect("changed", self._on_raw_changed)
        raw_view = Gtk.TextView(buffer=self._raw_buf)
        raw_view.set_monospace(True)
        raw_view.set_left_margin(8)
        raw_view.set_right_margin(8)
        raw_view.set_top_margin(8)
        raw_view.set_bottom_margin(8)

        raw_scroll = Gtk.ScrolledWindow()
        raw_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        raw_scroll.set_vexpand(True)
        raw_scroll.set_child(raw_view)

        raw_page = self._stack.add_titled(raw_scroll, "raw", "Raw CSS")
        raw_page.set_icon_name("text-editor-symbolic")

        # Raw Config tab
        self._cfg_buf = Gtk.TextBuffer()
        self._cfg_buf.connect("changed", self._on_cfg_changed)
        cfg_view = Gtk.TextView(buffer=self._cfg_buf)
        cfg_view.set_monospace(True)
        cfg_view.set_left_margin(8)
        cfg_view.set_right_margin(8)
        cfg_view.set_top_margin(8)
        cfg_view.set_bottom_margin(8)

        cfg_scroll = Gtk.ScrolledWindow()
        cfg_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        cfg_scroll.set_vexpand(True)
        cfg_scroll.set_child(cfg_view)

        self._cfg_error_bar = Gtk.InfoBar()
        self._cfg_error_bar.set_message_type(Gtk.MessageType.ERROR)
        self._cfg_error_label = Gtk.Label(label="")
        self._cfg_error_label.set_wrap(True)
        self._cfg_error_bar.add_child(self._cfg_error_label)
        self._cfg_error_bar.set_revealed(False)

        cfg_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        cfg_box.append(self._cfg_error_bar)
        cfg_box.append(cfg_scroll)

        cfg_page = self._stack.add_titled(cfg_box, "config", "Raw Config")
        cfg_page.set_icon_name("preferences-system-symbolic")

        # Switcher bar above the stack
        switcher = Adw.ViewSwitcherBar()
        switcher.set_stack(self._stack)
        switcher.set_reveal(True)

        self.append(switcher)
        self.append(self._stack)

    def load_preset(self, preset: Preset) -> None:
        self._preset = preset
        self._rebuild_colors()
        self._rebuild_spacing()
        self._raw_buf.set_text(preset.css_raw)
        self._cfg_buf.handler_block_by_func(self._on_cfg_changed)
        self._cfg_buf.set_text(preset.config_raw)
        self._cfg_buf.handler_unblock_by_func(self._on_cfg_changed)
        self._cfg_error_bar.set_revealed(False)

    def sync_config_raw(self, raw: str) -> None:
        """Update the Raw Config buffer from external changes (e.g. ModulesPanel)."""
        if self._preset is None:
            return
        self._preset.config_raw = raw
        self._cfg_buf.handler_block_by_func(self._on_cfg_changed)
        self._cfg_buf.set_text(raw)
        self._cfg_buf.handler_unblock_by_func(self._on_cfg_changed)
        self._cfg_error_bar.set_revealed(False)

    # ── Colors tab ────────────────────────────────────────────────────────────

    def _rebuild_colors(self) -> None:
        while child := self._colors_inner.get_first_child():
            self._colors_inner.remove(child)

        if not self._preset or not self._preset.css_vars:
            lbl = Gtk.Label(label="No @define-color variables found in style.css")
            lbl.add_css_class("dim-label")
            self._colors_inner.append(lbl)
            return

        group = Adw.PreferencesGroup(title="Color Variables")
        for var in self._preset.css_vars:
            row = self._make_color_row(var)
            group.add(row)
        self._colors_inner.append(group)

    def _make_color_row(self, var: CSSVar) -> Adw.ActionRow:
        row = Adw.ActionRow(title=var.name, subtitle=var.value)

        btn = Gtk.ColorButton()
        btn.set_valign(Gtk.Align.CENTER)
        rgba = _hex_to_rgba(var.value)
        btn.set_rgba(rgba)
        btn.set_use_alpha(True)
        btn.connect("color-set", self._on_color_set, var, row)
        row.add_suffix(btn)

        return row

    def _on_color_set(
        self, btn: Gtk.ColorButton, var: CSSVar, row: Adw.ActionRow
    ) -> None:
        if self._preset is None:
            return
        rgba = btn.get_rgba()
        new_value = _rgba_to_hex(rgba)
        var.value = new_value
        row.set_subtitle(new_value)
        self._preset.css_raw = update_css_var(self._preset.css_raw, var)
        # Sync raw tab buffer without re-triggering the change handler
        self._raw_buf.handler_block_by_func(self._on_raw_changed)
        self._raw_buf.set_text(self._preset.css_raw)
        self._raw_buf.handler_unblock_by_func(self._on_raw_changed)
        self._on_change()

    # ── Spacing tab ───────────────────────────────────────────────────────────

    def _rebuild_spacing(self) -> None:
        while child := self._spacing_inner.get_first_child():
            self._spacing_inner.remove(child)

        if self._preset is None:
            return

        group = Adw.PreferencesGroup(title="Layout & Spacing")

        # Build a quick lookup from parsed props
        prop_values: dict[tuple[str, str], str] = {
            (p.selector, p.prop): p.value
            for p in self._preset.css_props
        }

        for selector, prop, label, mn, mx in SPACING_PROPS:
            raw_val = prop_values.get((selector, prop), "0px")
            current = _parse_px(raw_val)
            row = self._make_slider_row(label, selector, prop, mn, mx, current)
            group.add(row)

        self._spacing_inner.append(group)

    def _make_slider_row(
        self, label: str, selector: str, prop: str,
        mn: int, mx: int, current: int
    ) -> Adw.ActionRow:
        row = Adw.ActionRow(title=label)
        row.set_subtitle(f"{selector}  ›  {prop}")

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.set_valign(Gtk.Align.CENTER)

        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, mn, mx, 1)
        scale.set_value(current)
        scale.set_size_request(160, -1)
        scale.set_draw_value(True)
        scale.set_value_pos(Gtk.PositionType.RIGHT)

        scale.connect("value-changed", self._on_scale_changed, selector, prop)
        box.append(scale)
        row.add_suffix(box)
        return row

    def _on_scale_changed(
        self, scale: Gtk.Scale, selector: str, prop: str
    ) -> None:
        if self._preset is None:
            return
        v = int(scale.get_value())
        new_val = f"{v}px"
        self._preset.css_raw = update_css_property(
            self._preset.css_raw, selector, prop, new_val
        )
        self._raw_buf.handler_block_by_func(self._on_raw_changed)
        self._raw_buf.set_text(self._preset.css_raw)
        self._raw_buf.handler_unblock_by_func(self._on_raw_changed)
        self._on_change()

    # ── Raw CSS tab ───────────────────────────────────────────────────────────

    def _on_raw_changed(self, buf: Gtk.TextBuffer) -> None:
        """Debounce raw edits — update preset css_raw and fire on_change."""
        if self._raw_debounce:
            GLib.source_remove(self._raw_debounce)
        self._raw_debounce = GLib.timeout_add(500, self._apply_raw_edit)

    def _apply_raw_edit(self) -> bool:
        self._raw_debounce = 0
        if self._preset is None:
            return GLib.SOURCE_REMOVE
        start = self._raw_buf.get_start_iter()
        end   = self._raw_buf.get_end_iter()
        self._preset.css_raw = self._raw_buf.get_text(start, end, False)
        # Re-parse so Colors and Spacing tabs reflect the edited text
        self._preset.css_vars, self._preset.css_props = parse_css(self._preset.css_raw)
        self._rebuild_colors()
        self._rebuild_spacing()
        self._on_change()
        return GLib.SOURCE_REMOVE

    # ── Raw Config tab ────────────────────────────────────────────────────────

    def _on_cfg_changed(self, buf: Gtk.TextBuffer) -> None:
        """Debounce raw config edits."""
        if self._cfg_debounce:
            GLib.source_remove(self._cfg_debounce)
        self._cfg_debounce = GLib.timeout_add(600, self._apply_cfg_edit)

    def _apply_cfg_edit(self) -> bool:
        self._cfg_debounce = 0
        if self._preset is None:
            return GLib.SOURCE_REMOVE
        start = self._cfg_buf.get_start_iter()
        end   = self._cfg_buf.get_end_iter()
        text  = self._cfg_buf.get_text(start, end, False)

        # Validate JSON before applying
        try:
            json.loads(strip_jsonc(text))
        except (json.JSONDecodeError, ValueError) as e:
            self._cfg_error_label.set_label(f"JSON error: {e}")
            self._cfg_error_bar.set_revealed(True)
            return GLib.SOURCE_REMOVE

        self._cfg_error_bar.set_revealed(False)
        self._preset.config_raw = text

        # Re-parse modules so ModulesPanel can be reloaded
        left, center, right = parse_config(text)
        self._preset.modules_left   = left
        self._preset.modules_center = center
        self._preset.modules_right  = right

        if self._on_module_config_parsed is not None:
            self._on_module_config_parsed(self._preset)

        self._on_change()
        return GLib.SOURCE_REMOVE
