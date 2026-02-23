# ==============================================================================
# CLOUD CENTER — modules/theme.py
# Embeds theme-ui via VTE. Shows current wallpaper as a native Gtk.Picture
# above the terminal — no sixel/kitty protocol needed.
# ==============================================================================

import os
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib

from base import BaseModule


class Module(BaseModule):
    name = "Theme"
    icon = "\uf53f"

    def build(self, on_escape=None) -> Gtk.Widget:
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        # ── Native wallpaper preview ──
        preview = self._build_preview()
        outer.append(preview)

        # ── Embedded TUI ──
        term = self.make_terminal("theme-ui", on_escape=on_escape)
        outer.append(term)

        return self.make_page(
            "Theme Manager",
            "Matugen wallpaper · scheme · contrast · presets",
            outer,
        )

    def _build_preview(self):
        state_file = os.path.expanduser(
        "~/.config/hypr/theme_state/current_wallpaper/current.jpg"
    )

    pic = Gtk.Picture()
    pic.set_hexpand(True)
    pic.set_vexpand(False)
    pic.set_content_fit(Gtk.ContentFit.COVER)
    pic.add_css_class("wallpaper-preview")

    # Wrap in a fixed-height box — Picture ignores size_request for height
    box = Gtk.Box()
    box.set_hexpand(True)
    box.set_vexpand(False)
    box.set_size_request(-1, 180)
    box.set_overflow(Gtk.Overflow.HIDDEN)
    box.add_css_class("preview-box")
    box.append(pic)

    def _load():
        if os.path.exists(state_file):
            pic.set_filename(state_file)

    _load()
    GLib.timeout_add(2000, lambda: (_load(), GLib.SOURCE_CONTINUE)[1])

    return box
