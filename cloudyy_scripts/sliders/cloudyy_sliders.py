#!/usr/bin/env python3
"""
cloudyy_sliders.py — Unified System Sliders
GTK4 + Libadwaita daemon widget. Single instance via D-Bus; re-running shows the window.

Backends:
  Volume      → wpctl (read/set); swayosd fires automatically via PipeWire hook
  Brightness  → brightnessctl (read/set); swayosd fires automatically via udev hook
  Night Light → hyprsunset via systemctl --user + hyprctl IPC (instant, no restart)
                Temp persisted to ~/.cache/wltemp (shared with wltemp.sh)

Window class (for Hyprland rules): class:^(org.cloudyy.sliders)$
"""

import gc
import os
import shutil
import subprocess
import sys
import tempfile
import threading

from pathlib import Path

# ──────────────────────────────────────────────────────────────────────────────
# GTK4 / Libadwaita
# ──────────────────────────────────────────────────────────────────────────────
try:
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gdk, GLib, Gio, Gtk
except ImportError as e:
    sys.exit(f"[cloudyy_sliders] GTK4/Libadwaita not found: {e}")

# ──────────────────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────────────────
APP_ID           = "org.cloudyy.sliders"
TEMP_CACHE       = Path.home() / ".cache" / "wltemp"
TEMP_MIN         = 1000
TEMP_MAX         = 6500
TEMP_DEFAULT     = 3500
HAS_HYPRSUNSET   = shutil.which("hyprsunset") is not None

# ══════════════════════════════════════════════════════════════════════════════
# BACKEND INTERFACES
# ══════════════════════════════════════════════════════════════════════════════

# ── Volume ────────────────────────────────────────────────────────────────────

def get_volume() -> float:
    try:
        parts = subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True, text=True,
        ).stdout.split()
        if len(parts) >= 2:
            return min(float(parts[1]) * 100, 100.0)
    except Exception:
        pass
    return 50.0


def is_muted() -> bool:
    try:
        return "[MUTED]" in subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True, text=True,
        ).stdout
    except Exception:
        return False


def set_volume(val: float) -> None:
    """wpctl set-volume. swayosd-server picks this up automatically via PipeWire."""
    v = round(val)
    try:
        subprocess.Popen(
            ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{v}%"],
            close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        if v > 0:
            subprocess.Popen(
                ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"],
                close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    except FileNotFoundError:
        pass


def toggle_mute() -> bool:
    """Toggle mute; returns the new muted state."""
    try:
        subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"], check=False)
    except FileNotFoundError:
        pass
    return is_muted()


# ── Brightness ────────────────────────────────────────────────────────────────

def get_brightness() -> float:
    try:
        cur  = float(subprocess.run(["brightnessctl", "get"], capture_output=True, text=True).stdout)
        maxv = float(subprocess.run(["brightnessctl", "max"], capture_output=True, text=True).stdout)
        if maxv > 0:
            return max((cur / maxv) * 100, 1.0)
    except Exception:
        pass
    # sysfs fallback
    try:
        for entry in os.scandir("/sys/class/backlight"):
            if entry.is_dir():
                cur  = float(open(f"{entry.path}/brightness").read())
                maxv = float(open(f"{entry.path}/max_brightness").read())
                return max((cur / maxv) * 100, 1.0)
    except Exception:
        pass
    return 50.0


def set_brightness(val: float) -> None:
    """brightnessctl set. swayosd-server picks this up automatically via udev."""
    v = max(round(val), 1)
    try:
        subprocess.Popen(
            ["brightnessctl", "set", f"{v}%", "-q"],
            close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except FileNotFoundError:
        pass


# ── Night Light (hyprsunset) ──────────────────────────────────────────────────
#
# hyprsunset exposes a Hyprland IPC command:
#   hyprctl hyprsunset temperature <kelvin>
# This is instant — no process restart needed, unlike wlsunset.
#
# Toggle uses systemctl --user start/stop hyprsunset.service with a direct
# Popen fallback for systems without the .service file.
#
# The slider is ALWAYS draggable:
#   - Active   → IPC fires on drag (debounced 200ms)
#   - Inactive → value is cached only; applied automatically on next toggle-on

_hs_active  = False
_hs_timer   = 0
_hs_pending = TEMP_DEFAULT


def _read_temp() -> float:
    try:
        return float(TEMP_CACHE.read_text().strip())
    except Exception:
        return float(TEMP_DEFAULT)


def _write_temp(val: float) -> None:
    """Atomic file replace so wltemp.sh and other tools see a consistent value."""
    tmp_path = None
    try:
        fd, tmp_path = tempfile.mkstemp(dir=TEMP_CACHE.parent, prefix=".wltemp_", suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            f.write(str(round(val)))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, TEMP_CACHE)
        tmp_path = None
    except OSError:
        pass
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def _ipc_set_temp(val: int) -> None:
    """Send hyprctl IPC in a background thread — never blocks GTK."""
    subprocess.Popen(
        ["hyprctl", "hyprsunset", "temperature", str(val)],
        close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    _write_temp(val)


def _debounced_apply(val: int) -> bool:
    """GLib timeout callback — fires 200ms after the last drag tick."""
    global _hs_timer
    _hs_timer = 0
    if _hs_active:
        threading.Thread(target=_ipc_set_temp, args=(val,), daemon=True).start()
    else:
        threading.Thread(target=_write_temp, args=(val,), daemon=True).start()
    return GLib.SOURCE_REMOVE


def get_hyprsunset() -> float:
    return _read_temp()


def set_hyprsunset(val: float) -> None:
    """Queue a debounced IPC call. Rapid drag ticks coalesce into one call."""
    global _hs_timer, _hs_pending
    _hs_pending = round(val)
    if _hs_timer:
        GLib.source_remove(_hs_timer)
    _hs_timer = GLib.timeout_add(200, _debounced_apply, _hs_pending)


def _start_hyprsunset_thread(temp: int) -> None:
    """Background thread: start service, wait for IPC socket, apply temp."""
    result = subprocess.run(
        ["systemctl", "--user", "start", "hyprsunset.service"],
        capture_output=True,
    )
    if result.returncode != 0:
        # No .service file — launch directly if not already running
        try:
            subprocess.run(["pgrep", "-x", "hyprsunset"], check=True, stdout=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            subprocess.Popen(
                ["hyprsunset"],
                start_new_session=True, close_fds=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
    import time; time.sleep(0.3)  # give compositor time to bind the IPC socket
    _ipc_set_temp(temp)


def start_hyprsunset(temp: int) -> None:
    global _hs_active
    _hs_active = True
    threading.Thread(target=_start_hyprsunset_thread, args=(temp,), daemon=True).start()


def stop_hyprsunset() -> None:
    global _hs_active
    _hs_active = False
    result = subprocess.run(
        ["systemctl", "--user", "stop", "hyprsunset.service"],
        capture_output=True,
    )
    if result.returncode != 0:
        subprocess.run(["pkill", "-x", "hyprsunset"], capture_output=True)


# ══════════════════════════════════════════════════════════════════════════════
# UI WIDGETS
# ══════════════════════════════════════════════════════════════════════════════

class SliderRow(Gtk.Box):
    """Standard icon → pill-slider → value-label row. Icon can be a toggle button."""

    def __init__(
        self,
        icon: str,
        css_name: str,
        min_v: float,
        max_v: float,
        step: float,
        fetch_fn,
        apply_fn,
        icon_tooltip: str = "",
        icon_click_fn=None,
    ):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        self.apply_fn = apply_fn
        self.add_css_class("slider-row")

        if icon_click_fn:
            self.icon_btn = Gtk.Button(label=icon)
            self.icon_btn.add_css_class("row-icon")
            self.icon_btn.add_css_class(f"icon-{css_name}")
            self.icon_btn.add_css_class("icon-btn")
            if icon_tooltip:
                self.icon_btn.set_tooltip_text(icon_tooltip)
            self.icon_btn.connect("clicked", lambda _: self._icon_clicked(icon_click_fn))
            self.append(self.icon_btn)
        else:
            lbl = Gtk.Label(label=icon)
            lbl.add_css_class("row-icon")
            lbl.add_css_class(f"icon-{css_name}")
            self.append(lbl)

        self.adj = Gtk.Adjustment(
            value=min_v, lower=min_v, upper=max_v,
            step_increment=step, page_increment=step * 10,
        )
        self.scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.adj)
        self.scale.set_hexpand(True)
        self.scale.set_draw_value(False)
        self.scale.add_css_class("pill-scale")
        self.scale.add_css_class(css_name)
        self.append(self.scale)

        self.val_lbl = Gtk.Label(label="--")
        self.val_lbl.set_width_chars(4)
        self.val_lbl.set_xalign(1.0)
        self.val_lbl.add_css_class("val-label")
        self.append(self.val_lbl)

        GLib.idle_add(self._lazy_init, fetch_fn)

    def _lazy_init(self, fetch_fn) -> bool:
        val = fetch_fn()
        self.adj.set_value(val)
        self.val_lbl.set_label(str(round(self.adj.get_value())))
        self.scale.connect("value-changed", self._on_value_changed)
        return GLib.SOURCE_REMOVE

    def _on_value_changed(self, scale) -> None:
        val = scale.get_value()
        self.val_lbl.set_label(str(round(val)))
        self.apply_fn(val)

    def _icon_clicked(self, fn) -> None:
        new_icon = fn()
        if new_icon and hasattr(self, "icon_btn"):
            self.icon_btn.set_label(new_icon)


class NightLightRow(Gtk.Box):
    """
    Night light row with moon/sun toggle + always-draggable temperature slider.

    - Dragging while active  → hyprctl IPC (debounced 200ms)
    - Dragging while inactive → caches value only; applied on next toggle-on
    - Track dims when inactive via CSS class, but remains fully interactive
    """

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        self.add_css_class("slider-row")

        self.toggle_btn = Gtk.Button()
        self.toggle_btn.add_css_class("row-icon")
        self.toggle_btn.add_css_class("icon-sunset")
        self.toggle_btn.add_css_class("icon-btn")
        self.toggle_btn.set_tooltip_text("Toggle night light")
        self.toggle_btn.connect("clicked", self._on_toggle)
        self.append(self.toggle_btn)

        init_temp = _read_temp()
        self.adj = Gtk.Adjustment(
            value=init_temp, lower=TEMP_MIN, upper=TEMP_MAX,
            step_increment=100, page_increment=500,
        )
        self.scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.adj)
        self.scale.set_hexpand(True)
        self.scale.set_draw_value(False)
        self.scale.add_css_class("pill-scale")
        self.scale.add_css_class("sunset")
        self.scale.connect("value-changed", self._on_value_changed)
        self.append(self.scale)

        self.val_lbl = Gtk.Label()
        self.val_lbl.set_width_chars(6)
        self.val_lbl.set_xalign(1.0)
        self.val_lbl.add_css_class("val-label")
        self.append(self.val_lbl)

        self._refresh_ui()
        self.val_lbl.set_label(f"{round(init_temp)}K")

    def _refresh_ui(self) -> None:
        self.toggle_btn.set_label("󰖙" if _hs_active else "󰖔")
        # Dim the track visually when off, but don't disable interactivity
        if _hs_active:
            self.scale.remove_css_class("inactive")
        else:
            self.scale.add_css_class("inactive")

    def _on_toggle(self, _btn) -> None:
        if _hs_active:
            stop_hyprsunset()
        else:
            start_hyprsunset(round(self.adj.get_value()))
        self._refresh_ui()

    def _on_value_changed(self, scale) -> None:
        val = scale.get_value()
        self.val_lbl.set_label(f"{round(val)}K")
        set_hyprsunset(val)


# ── Main Window ───────────────────────────────────────────────────────────────

class SliderWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_default_size(360, -1)
        self.set_resizable(False)
        self.set_decorated(False)
        self.connect("close-request", lambda _: self._hide())

        key_ctrl = Gtk.EventControllerKey()
        key_ctrl.connect("key-pressed", self._on_key_pressed)
        self.add_controller(key_ctrl)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(root)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        card.set_margin_start(14)
        card.set_margin_end(14)
        card.set_margin_top(14)
        card.set_margin_bottom(14)
        root.append(card)

        def _mute_toggle():
            return "󰖁" if toggle_mute() else ""

        card.append(SliderRow(
            icon="", css_name="volume",
            min_v=0, max_v=100, step=1,
            fetch_fn=get_volume, apply_fn=set_volume,
            icon_tooltip="Toggle mute", icon_click_fn=_mute_toggle,
        ))
        card.append(SliderRow(
            icon="󰃠", css_name="brightness",
            min_v=1, max_v=100, step=1,
            fetch_fn=get_brightness, apply_fn=set_brightness,
        ))
        if HAS_HYPRSUNSET:
            card.append(NightLightRow())

    def _hide(self) -> bool:
        self.set_visible(False)
        gc.collect()
        return True

    def _on_key_pressed(self, _ctrl, keyval, _code, _state) -> bool:
        if keyval == Gdk.KEY_Escape:
            self._hide()
            return True
        return False


# ══════════════════════════════════════════════════════════════════════════════
# APPLICATION
# ══════════════════════════════════════════════════════════════════════════════

APP_CSS = """
window {
    background-color: alpha(@window_bg_color, 0.92);
    border-radius: 12px;
    border: 1px solid alpha(white, 0.07);
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.55);
}
.slider-row {
    padding: 8px 4px;
    background: transparent;
}
scale.pill-scale trough {
    min-height: 14px;
    border-radius: 999px;
    background-color: rgba(255, 255, 255, 0.07);
}
scale.pill-scale highlight {
    min-height: 14px;
    border-radius: 999px;
}
/* Invisible thumb — the filled highlight acts as the visual handle */
scale.pill-scale slider {
    min-width: 0px; min-height: 0px;
    margin: 0px; padding: 0px;
    background: transparent; border: none; box-shadow: none;
}
scale.volume     highlight { background: linear-gradient(to right, #74c7ec, #89b4fa); }
scale.brightness highlight { background: linear-gradient(to right, #f9e2af, #fab387); }
scale.sunset     highlight { background: linear-gradient(to right, #fab387, #f38ba8); }
/* Dim sunset track when hyprsunset is off — still draggable */
scale.sunset.inactive trough    { opacity: 0.35; }
scale.sunset.inactive highlight { opacity: 0.35; }
.row-icon {
    font-size: 18px;
    font-family: "Symbols Nerd Font", "JetBrainsMono Nerd Font", monospace;
    min-width: 28px;
}
.icon-btn {
    background: transparent; border: none;
    padding: 2px 4px; border-radius: 6px;
}
.icon-btn:hover  { background: alpha(white, 0.08); }
.icon-btn:active { background: alpha(white, 0.13); }
.icon-volume     { color: #89b4fa; }
.icon-brightness { color: #f9e2af; }
.icon-sunset     { color: #fab387; }
.val-label {
    font-size: 12px; font-weight: 700;
    color: alpha(white, 0.5);
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-variant-numeric: tabular-nums;
}
"""


class SliderApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self._window: SliderWindow | None = None

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)
        self.hold()  # daemon mode — don't exit when window hides

        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.PREFER_DARK)

        provider = Gtk.CssProvider()
        provider.load_from_string(APP_CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
        )

        # Detect whether hyprsunset is already running at startup
        global _hs_active
        _hs_active = (
            subprocess.run(["pgrep", "-x", "hyprsunset"], capture_output=True).returncode == 0
        )

        self._window = SliderWindow(self)
        self._window.realize()
        self._window.set_visible(False)

    def do_activate(self) -> None:
        if self._window:
            self._window.present()

    def do_shutdown(self) -> None:
        """Flush any pending debounced write before exit."""
        global _hs_timer, _hs_pending
        if _hs_timer:
            GLib.source_remove(_hs_timer)
            _write_temp(_hs_pending)
        Adw.Application.do_shutdown(self)


if __name__ == "__main__":
    sys.exit(SliderApp().run(sys.argv))
