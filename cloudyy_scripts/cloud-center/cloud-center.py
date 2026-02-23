#!/usr/bin/env python3
# ==============================================================================
# CLOUD CENTER
# Universal control center for Hyprland/Arch.
# Modular: drop a new file in modules/ to add a section.
# ==============================================================================

import sys
import os
import importlib
import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")

from gi.repository import Gtk, Adw, Gio, GLib, Gdk

# ── Paths ──────────────────────────────────────────────────────────────────────

APP_DIR   = os.path.dirname(os.path.realpath(__file__))
MOD_DIR   = os.path.join(APP_DIR, "modules")
CSS_FILE  = os.path.join(APP_DIR, "assets", "style.css")

# All binaries live alongside cloud-center in cloudyy-other/
BIN_DIR   = APP_DIR

# ── Module registry ────────────────────────────────────────────────────────────
# Add entries here to register a new section.
# Each entry maps to modules/<id>.py which must define a Module class.
# Order here is the order in the sidebar.

REGISTRY = [
    # id           label            nerd-font glyph   category
    ("theme",     "Theme",         "",          "Appearance"),
    ("keybinds",  "Keybinds",      "",          "System"),
    ("configs",   "Configs",       "",          "System"),
    # ── Future modules go here ──
    # ("bluetooth", "Bluetooth",   "",          "Connectivity"),
    # ("wifi",      "Wi-Fi",       "",          "Connectivity"),
    # ("display",   "Display",     "",          "Hardware"),
    # ("audio",     "Audio",       "",          "Hardware"),
    # ("updates",   "Updates",     "",          "System"),
]

# ── Application ────────────────────────────────────────────────────────────────

class CloudCenter(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="com.cloudyy.CloudCenter",
            flags=Gio.ApplicationFlags.FLAGS_NONE,
        )
        self.connect("activate", self._on_activate)

    def _on_activate(self, app):
        win = MainWindow(application=app)
        win.present()


class MainWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("Cloud Center")
        self.set_default_size(1200, 750)
        self.set_size_request(900, 600)

        # Load CSS
        _load_css(CSS_FILE)

        # Build UI
        self._modules      = {}   # id → loaded module instance
        self._pages        = {}   # id → Gtk.Widget (built lazily)
        self._active_mod   = None # currently selected module id
        self._build_ui()

    def _build_ui(self):
        # Root: horizontal split — sidebar | content
        root = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        self.set_content(root)

        # ── Sidebar ──
        sidebar_scroll = Gtk.ScrolledWindow()
        sidebar_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sidebar_scroll.set_size_request(160, -1)
        sidebar_scroll.add_css_class("sidebar-scroll")

        self._sidebar_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._sidebar_box.add_css_class("sidebar")

        # App header inside sidebar
        header = self._build_sidebar_header()
        self._sidebar_box.append(header)

        # Group entries by category
        categories = {}
        for (mod_id, label, icon, category) in REGISTRY:
            categories.setdefault(category, []).append((mod_id, label, icon))

        self._row_buttons = {}  # id → button for selection state

        for cat_name, entries in categories.items():
            # Category label
            cat_label = Gtk.Label(label=cat_name.upper())
            cat_label.add_css_class("sidebar-category")
            cat_label.set_xalign(0)
            cat_label.set_margin_start(16)
            cat_label.set_margin_top(12)
            cat_label.set_margin_bottom(4)
            self._sidebar_box.append(cat_label)

            for (mod_id, label, icon) in entries:
                row = self._build_sidebar_row(mod_id, label, icon)
                self._sidebar_box.append(row)

        sidebar_scroll.set_child(self._sidebar_box)
        root.append(sidebar_scroll)

        # ── Separator ──
        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        sep.add_css_class("sidebar-sep")
        root.append(sep)

        # ── Content stack ──
        self._stack = Gtk.Stack()
        self._stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self._stack.set_transition_duration(120)
        self._stack.set_hexpand(True)
        self._stack.set_vexpand(True)

        # Welcome page
        welcome = self._build_welcome()
        self._stack.add_named(welcome, "welcome")

        root.append(self._stack)

        # Select first module by default
        if REGISTRY:
            first_id = REGISTRY[0][0]
            GLib.idle_add(self._select_module, first_id)

    def _build_sidebar_header(self):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.add_css_class("sidebar-header")
        box.set_margin_start(10)
        box.set_margin_end(10)
        box.set_margin_top(14)
        box.set_margin_bottom(10)

        icon = Gtk.Label(label="")
        icon.add_css_class("app-icon")
        box.append(icon)

        title = Gtk.Label(label="Cloud Center")
        title.add_css_class("app-title")
        title.set_xalign(0)
        box.append(title)

        return box

    def _build_sidebar_row(self, mod_id, label, glyph):
        btn = Gtk.Button()
        btn.add_css_class("sidebar-row")
        btn.set_has_frame(False)

        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        inner.set_margin_start(8)
        inner.set_margin_end(8)
        inner.set_margin_top(6)
        inner.set_margin_bottom(6)

        icon_lbl = Gtk.Label(label=glyph)
        icon_lbl.add_css_class("row-icon")
        inner.append(icon_lbl)

        lbl = Gtk.Label(label=label)
        lbl.set_xalign(0)
        lbl.set_hexpand(True)
        inner.append(lbl)

        btn.set_child(inner)
        btn.connect("clicked", lambda b, mid=mod_id: self._select_module(mid))

        self._row_buttons[mod_id] = btn
        return btn

    def _build_welcome(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_halign(Gtk.Align.CENTER)
        box.set_valign(Gtk.Align.CENTER)

        icon = Gtk.Label(label="")
        icon.add_css_class("welcome-icon")
        box.append(icon)

        lbl = Gtk.Label(label="Cloud Center")
        lbl.add_css_class("welcome-title")
        box.append(lbl)

        sub = Gtk.Label(label="Select a section from the sidebar")
        sub.add_css_class("welcome-sub")
        box.append(sub)

        return box

    def _select_module(self, mod_id):
        self._active_mod = mod_id
        # Update sidebar selection state
        for mid, btn in self._row_buttons.items():
            if mid == mod_id:
                btn.add_css_class("selected")
            else:
                btn.remove_css_class("selected")

        # Build page lazily on first visit
        if mod_id not in self._pages:
            widget = self._load_module_widget(mod_id)
            self._pages[mod_id] = widget
            self._stack.add_named(widget, mod_id)

        self._stack.set_visible_child_name(mod_id)

    def focus_sidebar(self):
        """Called by modules when Escape is pressed — moves focus to sidebar."""
        if self._active_mod:
            btn = self._row_buttons.get(self._active_mod)
            if btn:
                btn.grab_focus()

    def _load_module_widget(self, mod_id):
        try:
            sys.path.insert(0, MOD_DIR)
            mod = importlib.import_module(mod_id)
            instance = mod.Module(bin_dir=BIN_DIR)
            # Pass the focus_sidebar callback so modules can call it on Escape
            return instance.build(on_escape=self.focus_sidebar)
        except Exception as e:
            return self._error_page(mod_id, str(e))

    def _error_page(self, mod_id, msg):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_halign(Gtk.Align.CENTER)
        box.set_valign(Gtk.Align.CENTER)

        icon = Gtk.Label(label="")
        icon.add_css_class("error-icon")
        box.append(icon)

        lbl = Gtk.Label(label=f"Failed to load module: {mod_id}")
        lbl.add_css_class("error-title")
        box.append(lbl)

        detail = Gtk.Label(label=msg)
        detail.add_css_class("error-detail")
        detail.set_wrap(True)
        box.append(detail)

        return box


# ── CSS loader ─────────────────────────────────────────────────────────────────

def _load_css(path):
    provider = Gtk.CssProvider()
    if os.path.exists(path):
        provider.load_from_path(path)
    else:
        provider.load_from_data(b"")
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(),
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = CloudCenter()
    sys.exit(app.run(sys.argv))
