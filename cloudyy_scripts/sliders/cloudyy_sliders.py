#!/usr/bin/env python3
"""
cloudyy_sliders.py — System slider panel
Single-file GTK4/Libadwaita daemon. D-Bus single-instance — re-running raises the window.

Escape fix: uses set_accels_for_action("app.close") which is processed at the
application level before any widget (including Gtk.Scale) gets the event.
ShortcutController and EventControllerKey both lose to a focused Scale; this doesn't.

Hyprland window rule:  windowrulev2 = float, class:^(org.cloudyy.sliders)$
"""

import gc, os, shutil, subprocess, sys, tempfile, threading
from pathlib import Path

try:
    import gi
    gi.require_version("Gtk", "4.0")
    gi.require_version("Adw", "1")
    from gi.repository import Adw, Gdk, GLib, Gio, Gtk
except ImportError as e:
    sys.exit(f"cloudyy_sliders: GTK4/Libadwaita not found — {e}")

APP_ID         = "org.cloudyy.sliders"
TEMP_CACHE     = Path.home() / ".cache" / "wltemp"
ACTIVE_CACHE   = Path.home() / ".cache" / "wlnight_active"
TEMP_MIN       = 1000
TEMP_MAX       = 6500
TEMP_DEFAULT   = 3500
HAS_HYPRSUNSET = shutil.which("hyprsunset") is not None

# ══════════════════════════════════════════════════════════════════════════════
# BACKENDS
# ══════════════════════════════════════════════════════════════════════════════

# ── Volume ────────────────────────────────────────────────────────────────────

def get_volume() -> float:
    try:
        parts = subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True, text=True).stdout.split()
        return min(float(parts[1]) * 100, 100.0) if len(parts) >= 2 else 50.0
    except Exception:
        return 50.0

def is_muted() -> bool:
    try:
        return "[MUTED]" in subprocess.run(
            ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"],
            capture_output=True, text=True).stdout
    except Exception:
        return False

def set_volume(val: float) -> None:
    v = round(val)
    try:
        subprocess.Popen(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{v}%"],
                         close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if v > 0:
            subprocess.Popen(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"],
                             close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass

def toggle_mute() -> bool:
    try:
        subprocess.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"], check=False)
    except FileNotFoundError:
        pass
    return is_muted()

# ── Brightness ────────────────────────────────────────────────────────────────

def get_brightness() -> float:
    try:
        c = float(subprocess.run(["brightnessctl", "get"], capture_output=True, text=True).stdout)
        m = float(subprocess.run(["brightnessctl", "max"], capture_output=True, text=True).stdout)
        return max((c / m) * 100, 1.0) if m > 0 else 50.0
    except Exception:
        pass
    try:
        for e in os.scandir("/sys/class/backlight"):
            if e.is_dir():
                c = float(open(f"{e.path}/brightness").read())
                m = float(open(f"{e.path}/max_brightness").read())
                return max((c / m) * 100, 1.0)
    except Exception:
        pass
    return 50.0

def set_brightness(val: float) -> None:
    try:
        subprocess.Popen(["brightnessctl", "set", f"{max(round(val), 1)}%", "-q"],
                         close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        pass

# ── Hyprsunset ────────────────────────────────────────────────────────────────

_hs_active  = False
_hs_timer   = 0
_hs_pending = TEMP_DEFAULT

def _read_temp() -> float:
    try:
        return float(TEMP_CACHE.read_text().strip())
    except Exception:
        return float(TEMP_DEFAULT)

def _write_temp(val: float) -> None:
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=TEMP_CACHE.parent, prefix=".wltemp_", suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            f.write(str(round(val))); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, TEMP_CACHE); tmp = None
    except OSError:
        pass
    finally:
        if tmp:
            try: os.unlink(tmp)
            except OSError: pass

def _read_active() -> bool:
    try:
        return ACTIVE_CACHE.read_text().strip().lower() in {"true", "yes", "1", "on"}
    except Exception:
        return False

def _write_active(val: bool) -> None:
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=ACTIVE_CACHE.parent, prefix=".wlnight_", suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            f.write("true" if val else "false"); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, ACTIVE_CACHE); tmp = None
    except OSError:
        pass
    finally:
        if tmp:
            try: os.unlink(tmp)
            except OSError: pass

def _ipc_identity() -> None:
    subprocess.Popen(["hyprctl", "hyprsunset", "identity"],
                     close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def _ipc_temp(val: int) -> None:
    subprocess.Popen(["hyprctl", "hyprsunset", "temperature", str(val)],
                     close_fds=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    _write_temp(val)

def _debounce_fire(val: int) -> bool:
    global _hs_timer
    _hs_timer = 0
    fn = _ipc_temp if _hs_active else _write_temp
    threading.Thread(target=fn, args=(val,), daemon=True).start()
    return GLib.SOURCE_REMOVE

def set_hyprsunset(val: float) -> None:
    global _hs_timer, _hs_pending
    _hs_pending = round(val)
    if _hs_timer:
        GLib.source_remove(_hs_timer)
    _hs_timer = GLib.timeout_add(200, _debounce_fire, _hs_pending)

def _hs_start_thread(temp: int) -> None:
    if subprocess.run(["pgrep", "-x", "hyprsunset"],
                      capture_output=True).returncode != 0:
        r = subprocess.run(["systemctl", "--user", "start", "hyprsunset.service"],
                           capture_output=True)
        if r.returncode != 0:
            subprocess.Popen(["hyprsunset"], start_new_session=True, close_fds=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        import time; time.sleep(0.3)
    _ipc_temp(temp)
    _write_active(True)

def hs_start(temp: int) -> None:
    global _hs_active
    _hs_active = True
    threading.Thread(target=_hs_start_thread, args=(temp,), daemon=True).start()

def hs_stop() -> None:
    global _hs_active
    _hs_active = False
    _ipc_identity()
    _write_active(False)

# ══════════════════════════════════════════════════════════════════════════════
# WIDGETS
# ══════════════════════════════════════════════════════════════════════════════

class SliderRow(Gtk.Box):
    """icon → pill slider → value label. Icon is optionally a clickable toggle."""

    def __init__(self, icon: str, css: str, lo: float, hi: float, step: float,
                 fetch_fn, apply_fn, tip: str = "", icon_fn=None):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        self._apply = apply_fn
        self.add_css_class("row")

        if icon_fn:
            self._ibtn = Gtk.Button(label=icon)
            for c in ("icon", f"ic-{css}", "flat"):
                self._ibtn.add_css_class(c)
            if tip:
                self._ibtn.set_tooltip_text(tip)
            self._ibtn.connect("clicked", lambda _: self._icon_click(icon_fn))
            self.append(self._ibtn)
        else:
            lb = Gtk.Label(label=icon)
            for c in ("icon", f"ic-{css}"):
                lb.add_css_class(c)
            self.append(lb)

        self.adj = Gtk.Adjustment(value=lo, lower=lo, upper=hi,
                                  step_increment=step, page_increment=step * 10)
        self.sc = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.adj)
        self.sc.set_hexpand(True)
        self.sc.set_draw_value(False)
        for c in ("pill", css):
            self.sc.add_css_class(c)
        self.append(self.sc)

        self.lbl = Gtk.Label(label="--")
        self.lbl.set_width_chars(4)
        self.lbl.set_xalign(1.0)
        self.lbl.add_css_class("val")
        self.append(self.lbl)

        GLib.idle_add(self._boot, fetch_fn)

    def _boot(self, fetch_fn) -> bool:
        self.adj.set_value(fetch_fn())
        self.lbl.set_label(str(round(self.adj.get_value())))
        self.sc.connect("value-changed", self._slide)
        return GLib.SOURCE_REMOVE

    def _slide(self, sc) -> None:
        v = sc.get_value()
        self.lbl.set_label(str(round(v)))
        self._apply(v)

    def _icon_click(self, fn) -> None:
        r = fn()
        if r and hasattr(self, "_ibtn"):
            self._ibtn.set_label(r)


class NightRow(Gtk.Box):
    """Toggle icon + always-draggable temperature slider. Dims track when off."""

    def __init__(self):
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        self.add_css_class("row")

        self._btn = Gtk.Button()
        for c in ("icon", "ic-night", "flat"):
            self._btn.add_css_class(c)
        self._btn.set_tooltip_text("Toggle night light")
        self._btn.connect("clicked", self._toggle)
        self.append(self._btn)

        t = _read_temp()
        self.adj = Gtk.Adjustment(value=t, lower=TEMP_MIN, upper=TEMP_MAX,
                                  step_increment=100, page_increment=500)
        self.sc = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=self.adj)
        self.sc.set_hexpand(True)
        self.sc.set_draw_value(False)
        for c in ("pill", "night"):
            self.sc.add_css_class(c)
        self.sc.connect("value-changed", self._slide)
        self.append(self.sc)

        self.lbl = Gtk.Label()
        self.lbl.set_width_chars(6)
        self.lbl.set_xalign(1.0)
        self.lbl.add_css_class("val")
        self.append(self.lbl)

        self._sync()
        self.lbl.set_label(f"{round(t)}K")

    def _sync(self) -> None:
        self._btn.set_label("󰖙" if _hs_active else "󰖔")
        if _hs_active:
            self.sc.remove_css_class("dim")
        else:
            self.sc.add_css_class("dim")

    def _toggle(self, _) -> None:
        if _hs_active:
            hs_stop()
        else:
            hs_start(round(self.adj.get_value()))
        self._sync()

    def _slide(self, sc) -> None:
        v = sc.get_value()
        self.lbl.set_label(f"{round(v)}K")
        set_hyprsunset(v)


class Win(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app)
        self.set_default_size(360, -1)
        self.set_resizable(False)
        self.set_decorated(False)
        self.connect("close-request", lambda _: self._hide())

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(box)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        card.set_margin_start(14); card.set_margin_end(14)
        card.set_margin_top(14);   card.set_margin_bottom(14)
        box.append(card)

        card.append(SliderRow(
            "", "vol", 0, 100, 1,
            get_volume, set_volume,
            "Toggle mute", lambda: "󰖁" if toggle_mute() else "",
        ))
        card.append(SliderRow(
            "󰃠", "bright", 1, 100, 1,
            get_brightness, set_brightness,
        ))
        if HAS_HYPRSUNSET:
            card.append(NightRow())

    def _hide(self) -> bool:
        self.set_visible(False)
        gc.collect()
        return True  # prevent destroy


# ══════════════════════════════════════════════════════════════════════════════
# CSS
# ══════════════════════════════════════════════════════════════════════════════

CSS = """
window {
    background: alpha(@window_bg_color, 0.92);
    border-radius: 12px;
    border: 1px solid alpha(white, 0.07);
    box-shadow: 0 8px 32px rgba(0,0,0,0.55);
}
.row { padding: 8px 4px; background: transparent; }

scale.pill trough {
    min-height: 14px;
    border-radius: 999px;
    background: rgba(255,255,255,0.07);
}
scale.pill highlight { min-height: 14px; border-radius: 999px; }
scale.pill slider {
    min-width: 0; min-height: 0; margin: 0; padding: 0;
    background: transparent; border: none; box-shadow: none;
}

scale.vol    highlight { background: linear-gradient(to right, #74c7ec, #89b4fa); }
scale.bright highlight { background: linear-gradient(to right, #f9e2af, #fab387); }
scale.night  highlight { background: linear-gradient(to right, #fab387, #f38ba8); }

scale.dim trough    { opacity: 0.35; }
scale.dim highlight { opacity: 0.35; }

.icon {
    font-size: 18px;
    font-family: "Symbols Nerd Font", "JetBrainsMono Nerd Font", monospace;
    min-width: 28px;
}
.flat { background: transparent; border: none; padding: 2px 4px; border-radius: 6px; }
.flat:hover  { background: alpha(white, 0.08); }
.flat:active { background: alpha(white, 0.13); }

.ic-vol   { color: #89b4fa; }
.ic-bright{ color: #f9e2af; }
.ic-night { color: #fab387; }

.val {
    font-size: 12px;
    font-weight: 700;
    color: alpha(white, 0.5);
    font-family: "JetBrainsMono Nerd Font", monospace;
    font-variant-numeric: tabular-nums;
}
"""

# ══════════════════════════════════════════════════════════════════════════════
# APPLICATION
# ══════════════════════════════════════════════════════════════════════════════

class App(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self._win: Win | None = None

    def do_startup(self) -> None:
        Adw.Application.do_startup(self)
        self.hold()  # daemon mode: don't quit when window hides

        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.PREFER_DARK)

        p = Gtk.CssProvider()
        try:
            p.load_from_string(CSS)           # GTK >= 4.12
        except AttributeError:
            p.load_from_data(CSS.encode())    # GTK < 4.12 fallback
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

        # ── Escape to hide ────────────────────────────────────────────────────
        # set_accels_for_action is processed at the Gtk.Application level,
        # before any widget (including a focused Gtk.Scale) gets the event.
        # This is why EventControllerKey and ShortcutController both fail:
        # they're still in the widget event chain. This isn't.
        close_act = Gio.SimpleAction.new("close", None)
        close_act.connect("activate", lambda *_: self._win and self._win.set_visible(False))
        self.add_action(close_act)
        self.set_accels_for_action("app.close", ["Escape"])

        global _hs_active
        _hs_active = _read_active()
        if _hs_active and subprocess.run(
            ["pgrep", "-x", "hyprsunset"], capture_output=True
        ).returncode != 0:
            _hs_active = False
            _write_active(False)

        self._win = Win(self)
        self._win.realize()
        self._win.set_visible(False)

    def do_activate(self) -> None:
        if self._win:
            self._win.present()

    def do_shutdown(self) -> None:
        global _hs_timer, _hs_pending
        if _hs_timer:
            GLib.source_remove(_hs_timer)
            _write_temp(_hs_pending)
        Adw.Application.do_shutdown(self)


if __name__ == "__main__":
    sys.exit(App().run(sys.argv))
