#!/usr/bin/env python3
"""
waybar-editor/main.py
Standalone GTK4/Libadwaita waybar visual editor.

Launched as a subprocess from Cloud Center (or independently).
Three-panel layout:
  Left   — module list (toggle + reorder)
  Center — CSS property editors (Colors / Spacing / Raw tabs)
  Right  — live WebKit preview
"""
from __future__ import annotations

import logging
import subprocess
import sys
import os
import threading
from pathlib import Path

# Allow running from any working directory
sys.path.insert(0, str(Path(__file__).resolve().parent))

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] %(name)s: %(message)s",
    stream=sys.stderr,
)
log = logging.getLogger("waybar-editor")

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk

# Sanity-check that all panel files are present before importing them
_HERE = Path(__file__).resolve().parent
_REQUIRED = [
    _HERE / "models.py",
    _HERE / "parser.py",
    _HERE / "writer.py",
    _HERE / "panels" / "__init__.py",
    _HERE / "panels" / "modules.py",
    _HERE / "panels" / "properties.py",
    _HERE / "panels" / "preview.py",
]
_missing = [str(p) for p in _REQUIRED if not p.exists()]
if _missing:
    print("[waybar-editor] Missing files — did you copy the full waybar-editor/ directory?")
    for m in _missing:
        print(f"  MISSING: {m}")
    sys.exit(1)

from models import (
    CURRENT_FILE, WAYBAR_DIR,
    current_preset_name, list_presets,
)
from parser  import load_preset
from writer  import save_config, save_css, build_config_str

from panels.modules    import ModulesPanel
from panels.properties import PropertiesPanel
from panels.preview    import PreviewPanel

APP_ID = "dev.cloudyy.WaybarEditor"


class WaybarEditorWindow(Adw.ApplicationWindow):

    def __init__(self, app: Adw.Application) -> None:
        super().__init__(application=app, title="Waybar Editor")
        self.set_default_size(1400, 820)

        self._preset      = None
        self._dirty       = False
        self._toast_ov    = Adw.ToastOverlay()

        self._build_ui()
        self._load_current_preset()

    # ── UI ────────────────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        # Header bar
        header = Adw.HeaderBar()
        header.add_css_class("flat")

        # Preset selector
        self._preset_combo = Gtk.DropDown()
        presets = list_presets()
        self._preset_model = Gtk.StringList.new(presets)
        self._preset_combo.set_model(self._preset_model)
        self._preset_combo.set_tooltip_text("Active preset")
        self._preset_combo.connect("notify::selected", self._on_preset_selected)
        header.set_title_widget(self._preset_combo)

        # Save button
        self._save_btn = Gtk.Button(label="Save & Reload")
        self._save_btn.add_css_class("suggested-action")
        self._save_btn.connect("clicked", self._on_save)
        self._save_btn.set_sensitive(False)
        header.pack_end(self._save_btn)

        # Reload waybar button
        reload_btn = Gtk.Button()
        reload_btn.set_icon_name("view-refresh-symbolic")
        reload_btn.add_css_class("flat")
        reload_btn.set_tooltip_text("Reload waybar")
        reload_btn.connect("clicked", self._on_reload_waybar)
        header.pack_end(reload_btn)

        outer.append(header)

        # Three-panel body
        body = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        body.set_vexpand(True)

        # Left — modules (fixed width)
        left_frame = Gtk.Frame()
        self._modules_panel = ModulesPanel(on_change=self._on_modules_changed)
        left_frame.set_child(self._modules_panel)
        left_frame.set_size_request(240, -1)

        # Center — properties
        center_frame = Gtk.Frame()
        self._props_panel = PropertiesPanel(
            on_change=self._on_content_changed,
            on_module_config_parsed=self._on_module_config_parsed,
        )
        center_frame.set_child(self._props_panel)

        # Right — preview
        right_frame = Gtk.Frame()
        self._preview_panel = PreviewPanel()
        right_frame.set_child(self._preview_panel)

        left_pane = Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        left_pane.set_start_child(left_frame)
        left_pane.set_end_child(center_frame)
        left_pane.set_position(260)
        left_pane.set_shrink_start_child(False)
        left_pane.set_shrink_end_child(False)

        body.set_start_child(left_pane)
        body.set_end_child(right_frame)
        body.set_position(560)
        body.set_shrink_start_child(False)
        body.set_shrink_end_child(False)

        outer.append(body)

        self._toast_ov.set_child(outer)
        self.set_content(self._toast_ov)

    # ── Preset loading ────────────────────────────────────────────────────────

    def _load_current_preset(self) -> None:
        name    = current_preset_name()
        presets = list_presets()
        if not presets:
            self._show_toast("No presets found in ~/.config/waybar/presets/")
            return

        # Select matching item in dropdown
        idx = presets.index(name) if name in presets else 0
        self._preset_combo.set_selected(idx)
        self._load_preset(presets[idx])

    def _load_preset(self, name: str) -> None:
        preset = load_preset(name)
        if preset is None:
            self._show_toast(f"Could not load preset: {name}")
            return
        self._preset = preset
        self._dirty  = False
        self._save_btn.set_sensitive(False)
        self.set_title(f"Waybar Editor — {name}")

        self._modules_panel.load_preset(preset)
        self._props_panel.load_preset(preset)
        self._preview_panel.load_preset(preset)
        log.info("Loaded preset: %s", name)

    def _on_preset_selected(self, combo: Gtk.DropDown, _param) -> None:
        idx  = combo.get_selected()
        item = self._preset_model.get_item(idx)
        if item:
            self._load_preset(item.get_string())

    # ── Change tracking ───────────────────────────────────────────────────────

    def _on_content_changed(self) -> None:
        self._dirty = True
        self._save_btn.set_sensitive(True)
        self._preview_panel.schedule_refresh()

    def _on_modules_changed(self) -> None:
        """Called by ModulesPanel on toggle/reorder — sync raw config buffer."""
        self._on_content_changed()
        if self._preset is not None:
            raw = build_config_str(self._preset)
            self._props_panel.sync_config_raw(raw)

    def _on_module_config_parsed(self, preset) -> None:
        """Called by PropertiesPanel after raw config edit updates module lists."""
        self._modules_panel.load_preset(preset)

    # ── Save ──────────────────────────────────────────────────────────────────

    def _on_save(self, _btn: Gtk.Button) -> None:
        if self._preset is None:
            return
        try:
            save_css(self._preset)
            save_config(self._preset)
        except Exception as e:
            self._show_toast(f"Save failed: {e}")
            log.error("Save failed: %s", e)
            return

        self._dirty = False
        self._save_btn.set_sensitive(False)
        self._show_toast(f"Saved — reloading waybar…")
        self._reload_waybar()

    def _on_reload_waybar(self, _btn: Gtk.Button) -> None:
        self._reload_waybar()
        self._show_toast("Waybar reloaded")

    def _reload_waybar(self) -> None:
        def _worker() -> None:
            subprocess.Popen(
                ["bash", "-c",
                 "pkill waybar 2>/dev/null || true; sleep 0.3; "
                 "if command -v uwsm-app &>/dev/null; then uwsm-app -- waybar; "
                 "else waybar; fi"],
                start_new_session=True,
            )
        threading.Thread(target=_worker, daemon=True).start()

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _show_toast(self, msg: str) -> None:
        toast = Adw.Toast(title=msg)
        self._toast_ov.add_toast(toast)


class WaybarEditorApp(Adw.Application):

    def __init__(self) -> None:
        super().__init__(
            application_id=APP_ID,
            flags=Gio.ApplicationFlags.DEFAULT_FLAGS,
        )

    def do_activate(self) -> None:
        win = WaybarEditorWindow(self)
        win.present()


def main() -> None:
    app = WaybarEditorApp()
    app.run(sys.argv)


if __name__ == "__main__":
    main()
