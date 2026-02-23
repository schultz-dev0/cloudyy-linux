# ==============================================================================
# CLOUD CENTER — modules/configs.py
# Embeds hcm (Hyprland Config Manager) inside a VTE terminal widget.
# ==============================================================================

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk

from base import BaseModule


class Module(BaseModule):
    name = "Configs"
    icon = "text-editor"

    def build(self, on_escape=None) -> Gtk.Widget:
        term = self.make_terminal("hcm", on_escape=on_escape)
        return self.make_page(
            "Config Manager",
            "Browse and edit Hyprland configuration files",
            term,
        )
