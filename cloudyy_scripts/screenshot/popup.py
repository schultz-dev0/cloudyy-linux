#!/usr/bin/env python3
import os
import signal
import subprocess
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("GdkPixbuf", "2.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gio, Gtk
from gi.repository import Gtk4LayerShell as GtkLayerShell

POPUP_WIDTH = 220
# Bar: barHeight(40) + topGap(6) + visual gap(8)
MARGIN_TOP = 54


class ScreenshotPopup(Gtk.ApplicationWindow):
    def __init__(self, app, temp_path):
        super().__init__(application=app)
        self.temp_path = os.path.abspath(temp_path)
        self._setup_layer_shell()
        self._apply_css()
        self._build_ui()

    def _setup_layer_shell(self):
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.TOP)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, MARGIN_TOP)
        GtkLayerShell.set_exclusive_zone(self, 0)
        GtkLayerShell.set_namespace(self, "screenshot-popup")
        self.set_decorated(False)
        self.set_resizable(False)

    def _apply_css(self):
        css = Gtk.CssProvider()
        css.load_from_string("""
            window { background: transparent; }
            .popup-root {
                background: rgba(18, 18, 35, 0.96);
                border-radius: 14px;
                box-shadow: 0 8px 32px rgba(0,0,0,0.6);
                overflow: hidden;
            }
            .overlay-btn {
                background: rgba(0, 0, 0, 0.4);
                color: rgba(255, 255, 255, 0.85);
                border-radius: 8px;
                padding: 6px;
                min-width: 24px;
                min-height: 24px;
                border: none;
            }
            .overlay-btn:hover { 
                background: rgba(0, 0, 0, 0.7); 
                color: white;
            }
            .drag-hint {
                font-size: 10px;
                color: rgba(255,255,255,0.45);
            }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

    def _build_ui(self):
        # Load and scale the image down using Pixbuf to strictly constrain natural size
        pixbuf = GdkPixbuf.Pixbuf.new_from_file(self.temp_path)
        orig_w = pixbuf.get_width()
        orig_h = pixbuf.get_height()

        # Calculate aspect ratio
        thumb_h = int(orig_h * (POPUP_WIDTH / orig_w)) if orig_w > 0 else 120
        # Hard cap the height so it doesn't get too tall on vertical displays
        thumb_h = min(thumb_h, 160)

        pixbuf = pixbuf.scale_simple(
            POPUP_WIDTH, thumb_h, GdkPixbuf.InterpType.BILINEAR
        )
        texture = Gdk.Texture.new_for_pixbuf(pixbuf)

        self.set_default_size(POPUP_WIDTH, thumb_h)
        self.set_size_request(POPUP_WIDTH, thumb_h)

        overlay = Gtk.Overlay()
        overlay.add_css_class("popup-root")
        overlay.set_size_request(POPUP_WIDTH, thumb_h)

        picture = Gtk.Picture.new_for_paintable(texture)
        picture.set_content_fit(Gtk.ContentFit.CONTAIN)
        picture.set_can_shrink(True)
        overlay.set_child(picture)

        # Buttons (top)
        btn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        btn_row.set_halign(Gtk.Align.FILL)
        btn_row.set_valign(Gtk.Align.START)
        btn_row.set_margin_top(6)
        btn_row.set_margin_start(6)
        btn_row.set_margin_end(6)

        btn_copy = Gtk.Button(icon_name="edit-copy-symbolic")
        btn_copy.add_css_class("overlay-btn")
        btn_copy.connect("clicked", lambda _: self._copy_and_close())

        spacer = Gtk.Box()
        spacer.set_hexpand(True)

        btn_close = Gtk.Button(icon_name="window-close-symbolic")
        btn_close.add_css_class("overlay-btn")
        btn_close.connect("clicked", lambda _: self._close())

        btn_row.append(btn_copy)
        btn_row.append(spacer)
        btn_row.append(btn_close)
        overlay.add_overlay(btn_row)

        # Drag hint (bottom)
        hint = Gtk.Label(label="⠿  drag to upload")
        hint.add_css_class("drag-hint")
        hint.set_halign(Gtk.Align.CENTER)
        hint.set_valign(Gtk.Align.END)
        hint.set_margin_bottom(5)
        overlay.add_overlay(hint)

        # Drag source on the entire overlay
        drag = Gtk.DragSource.new()
        drag.set_actions(Gdk.DragAction.COPY)
        drag.connect("prepare", self._on_drag_prepare)
        drag.connect("drag-end", lambda *_: self._close_after_drag())
        overlay.add_controller(drag)

        revealer = Gtk.Revealer()
        revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        revealer.set_transition_duration(180)
        revealer.set_reveal_child(False)
        revealer.set_child(overlay)
        self.set_child(revealer)
        GLib.idle_add(lambda: revealer.set_reveal_child(True) or False)

    def _on_drag_prepare(self, source, x, y):
        # Set the drag icon to the screenshot itself
        texture = Gdk.Texture.new_from_file(Gio.File.new_for_path(self.temp_path))
        source.set_icon(texture, x, y)

        uri = Gio.File.new_for_path(self.temp_path).get_uri()
        data = GLib.Bytes.new((uri + "\r\n").encode("utf-8"))
        return Gdk.ContentProvider.new_for_bytes("text/uri-list", data)

    def _copy_and_close(self):
        with open(self.temp_path, "rb") as f:
            subprocess.run(["wl-copy", "--type", "image/png"], stdin=f, check=False)
        self._close()

    def _close_after_drag(self):
        # Give the drop target time to read the file before deleting it
        import shlex

        subprocess.Popen(
            ["sh", "-c", f"sleep 60 && rm -f -- {shlex.quote(self.temp_path)}"]
        )
        self.get_application().quit()

    def _close(self):
        try:
            os.unlink(self.temp_path)
        except FileNotFoundError:
            pass
        self.get_application().quit()


class ScreenshotApp(Gtk.Application):
    def __init__(self, temp_path):
        super().__init__(application_id="com.cloudyy.screenshot-popup")
        self._temp_path = temp_path
        self.connect(
            "activate", lambda app: ScreenshotPopup(app, self._temp_path).present()
        )


def main():
    if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
        print("Usage: popup.py <screenshot_path>", file=sys.stderr)
        sys.exit(1)

    temp_path = sys.argv[1]

    def _sigterm(*_):
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, _sigterm)
    sys.exit(ScreenshotApp(temp_path).run([]))


if __name__ == "__main__":
    main()
