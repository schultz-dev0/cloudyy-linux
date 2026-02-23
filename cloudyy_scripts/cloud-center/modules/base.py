# ==============================================================================
# CLOUD CENTER — modules/base.py
# Base class all modules inherit from.
# To create a new module:
#   1. Create modules/<id>.py
#   2. Define a class Module(BaseModule)
#   3. Set class attributes: name, icon
#   4. Implement build() → Gtk.Widget
#   5. Add an entry to REGISTRY in cloud-center.py
# ==============================================================================

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Vte", "3.91")
from gi.repository import Gtk, Vte, GLib, Gdk
import os


class BaseModule:
    """Base class for all Cloud Center modules."""

    name: str = "Module"
    icon: str = "application-x-executable"

    def __init__(self, bin_dir: str):
        self.bin_dir = bin_dir

    def build(self) -> Gtk.Widget:
        """Return the root widget for this module. Override in subclasses."""
        raise NotImplementedError

    # ── VTE helpers ────────────────────────────────────────────────────────────

    def make_terminal(self, command: str, on_escape=None) -> Vte.Terminal:
        """
        Create a VTE terminal widget running `command`.
        Looks for the binary in bin_dir first, then falls back to $PATH.

        on_escape: optional callable — called when Escape is pressed inside
                   the terminal (used by Cloud Center to return focus to sidebar).
        """
        from gi.repository import Pango
        term = Vte.Terminal()
        term.set_hexpand(True)
        term.set_vexpand(True)
        term.add_css_class("embedded-terminal")
        term.set_clear_background(False)

        # Enable sixel — VTE 0.70+. Sixel is the only image protocol VTE
        # supports; kitty graphics protocol is not available inside VTE.
        try:
            term.set_enable_sixel(True)
        except AttributeError:
            pass

        # Set font explicitly so cell dimensions are known
        font_desc = Pango.FontDescription.from_string("JetBrainsMono Nerd Font 11")
        term.set_font(font_desc)

        # ── Escape key: intercept at VTE level before VTE consumes it ──
        # Window-level EventControllerKey never fires when VTE has focus.
        if on_escape is not None:
            key_ctrl = Gtk.EventControllerKey()
            def _on_key(ctrl, keyval, keycode, state, cb=on_escape):
                if keyval == Gdk.KEY_Escape:
                    cb()
                    return True   # consumed — don't pass to VTE
                return False      # let VTE handle everything else
            key_ctrl.connect("key-pressed", _on_key)
            term.add_controller(key_ctrl)

        # Resolve binary
        local_bin = os.path.join(self.bin_dir, command)
        argv = [local_bin] if (
            os.path.isfile(local_bin) and os.access(local_bin, os.X_OK)
        ) else [command]

        # Tell ratatui-image to use sixel by advertising it via TERM
        # TERM=xterm doesn't advertise sixel; we set a custom var instead
        # and theme-ui reads CLOUD_CENTER=1 to force sixel protocol
        env = os.environ.copy()
        env["TERM"]         = "xterm-256color"
        env["CLOUD_CENTER"] = "1"   # signals theme-ui to force sixel picker

        term.spawn_async(
            Vte.PtyFlags.DEFAULT,
            None, argv,
            [f"{k}={v}" for k, v in env.items()],
            GLib.SpawnFlags.SEARCH_PATH,
            None, None, -1, None,
            self._on_spawn_done, None,
        )

        term.connect("child-exited", lambda t, s, cmd=command: self._restart(t, cmd))
        return term

    def _on_spawn_done(self, terminal, pid, error, user_data):
        if error:
            print(f"[CloudCenter] spawn error: {error.message}")

    def _restart(self, term: Vte.Terminal, command: str):
        """Re-spawn the command after a brief pause when it exits."""
        GLib.timeout_add(800, lambda: self._do_restart(term, command))

    def _do_restart(self, term: Vte.Terminal, command: str):
        local_bin = os.path.join(self.bin_dir, command)
        argv = [local_bin] if (
            os.path.isfile(local_bin) and os.access(local_bin, os.X_OK)
        ) else [command]

        env = os.environ.copy()
        env["TERM"] = "xterm-256color"

        term.spawn_async(
            Vte.PtyFlags.DEFAULT,
            None, argv,
            [f"{k}={v}" for k, v in env.items()],
            GLib.SpawnFlags.SEARCH_PATH,
            None, None, -1, None,
            self._on_spawn_done, None,
        )
        return GLib.SOURCE_REMOVE

    # ── Layout helpers ─────────────────────────────────────────────────────────

    def make_page(self, title: str, subtitle: str, content: Gtk.Widget) -> Gtk.Widget:
        """Wrap content in a standard page with a title bar."""
        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        outer.add_css_class("module-page")

        # Header
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        header.add_css_class("module-header")
        header.set_margin_start(20)
        header.set_margin_end(20)
        header.set_margin_top(16)
        header.set_margin_bottom(14)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_lbl = Gtk.Label(label=title)
        title_lbl.set_xalign(0)
        title_lbl.add_css_class("page-title")

        sub_lbl = Gtk.Label(label=subtitle)
        sub_lbl.set_xalign(0)
        sub_lbl.add_css_class("page-subtitle")

        text_box.append(title_lbl)
        text_box.append(sub_lbl)
        header.append(text_box)
        outer.append(header)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        sep.add_css_class("page-sep")
        outer.append(sep)

        outer.append(content)
        return outer
