# ==============================================================================
# CLOUD CENTER — modules/keybinds.py
# Embeds hkbm (Hyprland Keybind Manager) inside a VTE terminal widget.
# ==============================================================================

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk

from base import BaseModule


class Module(BaseModule):
    name = "Keybinds"
    icon = "preferences-desktop-keyboard"

    def build(self, on_escape=None) -> Gtk.Widget:
        term = self.make_terminal("hkbm", on_escape=on_escape)
        return self.make_page(
            "Keybind Manager",
            "View and manage Hyprland keybindings",
            term,
        )
