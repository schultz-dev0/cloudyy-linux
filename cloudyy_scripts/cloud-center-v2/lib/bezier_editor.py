"""Cloud Center — self-contained Bezier curve editor for Hyprland animations.

No hyprland_state dependency. Stores user curves in
~/.config/cloud-center/bezier_curves.json and applies via hyprctl.
"""
from __future__ import annotations

import json
import logging
import math
import subprocess
import threading
from pathlib import Path
from typing import Callable, Optional

from gi.repository import Adw, GLib, Gtk

log = logging.getLogger(__name__)

# ── Persistence ───────────────────────────────────────────────────────────────

_CURVES_PATH = Path.home() / ".config" / "cloud-center" / "bezier_curves.json"

# ── Built-in CSS easing presets ───────────────────────────────────────────────

BUILTIN_PRESETS: dict[str, tuple[float, float, float, float]] = {
    "ease":            (0.25, 0.10, 0.25, 1.00),
    "easeIn":          (0.42, 0.00, 1.00, 1.00),
    "easeOut":         (0.00, 0.00, 0.58, 1.00),
    "easeInOut":       (0.42, 0.00, 0.58, 1.00),
    "easeOutBack":     (0.34, 1.56, 0.64, 1.00),
    "easeInOutBack":   (0.68, -0.60, 0.32, 1.60),
    "easeOutExpo":     (0.16, 1.00, 0.30, 1.00),
    "easeOutCubic":    (0.33, 1.00, 0.68, 1.00),
    "easeOutQuad":     (0.50, 1.00, 0.89, 1.00),
    "easeInOutSine":   (0.37, 0.00, 0.63, 1.00),
    "linear":          (0.00, 0.00, 1.00, 1.00),
}

# ── Bezier math ───────────────────────────────────────────────────────────────

def _cubic(t: float, p1: float, p2: float) -> float:
    return 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3


def _solve_t(x: float, x1: float, x2: float, eps: float = 1e-6) -> float:
    t = x
    for _ in range(20):
        fx = _cubic(t, x1, x2)
        dx = 3 * (1 - t) ** 2 * x1 + 6 * (1 - t) * t * (x2 - x1) + 3 * t ** 2 * (1 - x2)
        if abs(dx) < eps:
            break
        t -= (fx - x) / dx
        t = max(0.0, min(1.0, t))
    return t


def ease(p: float, x1: float, y1: float, x2: float, y2: float) -> float:
    t = _solve_t(p, x1, x2)
    return _cubic(t, y1, y2)


# ── User curve store ──────────────────────────────────────────────────────────

class CurveStore:
    def __init__(self) -> None:
        self._user: dict[str, tuple[float, float, float, float]] = {}
        self._load()

    def _load(self) -> None:
        if _CURVES_PATH.exists():
            try:
                raw = json.loads(_CURVES_PATH.read_text(encoding="utf-8"))
                self._user = {k: tuple(v) for k, v in raw.items()}  # type: ignore[misc]
            except Exception:
                self._user = {}

    def _save(self) -> None:
        _CURVES_PATH.parent.mkdir(parents=True, exist_ok=True)
        _CURVES_PATH.write_text(
            json.dumps({k: list(v) for k, v in self._user.items()}, indent=2),
            encoding="utf-8",
        )

    def all_names(self) -> list[str]:
        return list(BUILTIN_PRESETS) + list(self._user)

    def user_names(self) -> list[str]:
        return list(self._user)

    def is_builtin(self, name: str) -> bool:
        return name in BUILTIN_PRESETS

    def get_points(self, name: str) -> tuple[float, float, float, float] | None:
        if name in BUILTIN_PRESETS:
            return BUILTIN_PRESETS[name]
        return self._user.get(name)

    def save(self, name: str, pts: tuple[float, float, float, float]) -> None:
        self._user[name] = pts
        self._save()

    def delete(self, name: str) -> None:
        self._user.pop(name, None)
        self._save()

    def rename(self, old: str, new: str) -> None:
        if old in self._user:
            self._user[new] = self._user.pop(old)
            self._save()

    def next_name(self) -> str:
        i = 1
        while f"myBezier{i}" in self._user:
            i += 1
        return f"myBezier{i}"


_STORE: CurveStore | None = None

def _store() -> CurveStore:
    global _STORE
    if _STORE is None:
        _STORE = CurveStore()
    return _STORE


def _invalidate_store() -> None:
    global _STORE
    _STORE = None


# ── Accent colour helper ──────────────────────────────────────────────────────

def _accent_rgb() -> tuple[float, float, float]:
    try:
        manager = Adw.StyleManager.get_default()
        color = manager.get_accent_color()
        rgba = color.to_rgba()
        return rgba.red, rgba.green, rgba.blue
    except Exception:
        return 0.35, 0.72, 0.98


# ── Canvas ─────────────────────────────────────────────────────────────────────

_HANDLE_R = 8
_PAD = 16


class BezierCanvas(Gtk.DrawingArea):
    """Interactive Cairo-based bezier canvas with two draggable control points."""

    def __init__(
        self,
        on_change: Callable | None = None,
        on_drag_end: Callable | None = None,
    ) -> None:
        super().__init__()
        self.x1, self.y1 = 0.25, 0.10
        self.x2, self.y2 = 0.25, 1.00
        self._dragging: str | None = None
        self._drag_scale = 1.0
        self._drag_ox = 0.0
        self._drag_oy = 0.0
        self._view_y_lo = -0.1
        self._view_y_hi = 1.1
        self._on_change = on_change
        self._on_drag_end = on_drag_end

        self.set_content_width(260)
        self.set_content_height(260)
        self.set_draw_func(self._draw)

        drag = Gtk.GestureDrag()
        drag.connect("drag-begin", self._drag_begin)
        drag.connect("drag-update", self._drag_update)
        drag.connect("drag-end", self._drag_done)
        self.add_controller(drag)

        motion = Gtk.EventControllerMotion()
        motion.connect("motion", self._motion)
        self.add_controller(motion)

    @property
    def is_dragging(self) -> bool:
        return self._dragging is not None

    def set_points(self, x1: float, y1: float, x2: float, y2: float) -> None:
        self.x1, self.y1, self.x2, self.y2 = x1, y1, x2, y2
        self._snap_range()
        self.queue_draw()

    def _snap_range(self) -> None:
        margin = 0.12
        self._view_y_lo = min(0.0, self.y1, self.y2) - margin
        self._view_y_hi = max(1.0, self.y1, self.y2) + margin

    def _metrics(self):
        w, h = self.get_width(), self.get_height()
        y_span = self._view_y_hi - self._view_y_lo
        pad = _PAD + _HANDLE_R
        scale = min((w - 2 * pad) / 1.0, (h - 2 * pad) / y_span)
        x_off = (w - scale) / 2
        y_off = (h - y_span * scale) / 2
        return scale, x_off, y_off

    def _to_px(self, bx: float, by: float):
        s, xo, yo = self._metrics()
        return xo + bx * s, yo + (self._view_y_hi - by) * s

    def _from_px(self, cx: float, cy: float):
        s, xo, yo = self._metrics()
        return (cx - xo) / s, self._view_y_hi - (cy - yo) / s

    def _hit(self, cx: float, cy: float) -> str | None:
        r2 = (_HANDLE_R + 4) ** 2
        p1 = self._to_px(self.x1, self.y1)
        p2 = self._to_px(self.x2, self.y2)
        if (cx - p1[0]) ** 2 + (cy - p1[1]) ** 2 <= r2:
            return "p1"
        if (cx - p2[0]) ** 2 + (cy - p2[1]) ** 2 <= r2:
            return "p2"
        return None

    def _drag_begin(self, _g, x: float, y: float) -> None:
        hit = self._hit(x, y)
        if not hit:
            self._dragging = None
            return
        self._dragging = hit
        self._drag_scale, *_ = self._metrics()
        if hit == "p1":
            self._drag_ox, self._drag_oy = self.x1, self.y1
        else:
            self._drag_ox, self._drag_oy = self.x2, self.y2
        try:
            cursor = Gtk.Cursor.new_from_name("none")
            self.set_cursor(cursor)
        except Exception:
            pass

    def _drag_update(self, _g, dx: float, dy: float) -> None:
        if not self._dragging:
            return
        s = self._drag_scale
        bx = max(0.0, min(1.0, round(self._drag_ox + dx / s, 3)))
        by = round(self._drag_oy - dy / s, 3)
        if self._dragging == "p1":
            self.x1, self.y1 = bx, by
        else:
            self.x2, self.y2 = bx, by
        self._snap_range()
        self.queue_draw()
        if self._on_change:
            self._on_change(self.x1, self.y1, self.x2, self.y2)

    def _drag_done(self, _g, *_) -> None:
        self._dragging = None
        self.set_cursor(None)
        self.queue_draw()
        if self._on_drag_end:
            self._on_drag_end()

    def _motion(self, _ctrl, x: float, y: float) -> None:
        if self._dragging:
            return
        try:
            name = "grab" if self._hit(x, y) else "default"
            self.set_cursor(Gtk.Cursor.new_from_name(name))
        except Exception:
            pass

    def _draw(self, _area, cr, w: int, h: int) -> None:  # type: ignore[override]
        s, xo, yo = self._metrics()
        # Grid corners
        gx0, gy0 = self._to_px(0, 0)
        gx1, gy1 = self._to_px(1, 1)
        gw = gx1 - gx0
        gh = gy0 - gy1

        fg = self.get_color()
        r, g, b = fg.red, fg.green, fg.blue

        # Grid lines
        cr.set_source_rgba(r, g, b, 0.07)
        cr.set_line_width(0.5)
        for i in range(11):
            f = i / 10
            cr.move_to(gx0 + f * gw, gy1)
            cr.line_to(gx0 + f * gw, gy0)
            cr.move_to(gx0, gy1 + f * gh)
            cr.line_to(gx1, gy1 + f * gh)
        cr.stroke()

        # Border
        cr.set_source_rgba(r, g, b, 0.22)
        cr.set_line_width(1.0)
        cr.rectangle(gx0, gy1, gw, gh)
        cr.stroke()

        # Linear reference
        cr.set_source_rgba(r, g, b, 0.14)
        cr.set_line_width(1.0)
        cr.set_dash([4.0, 4.0])
        cr.move_to(*self._to_px(0, 0))
        cr.line_to(*self._to_px(1, 1))
        cr.stroke()
        cr.set_dash([])

        # Control lines
        p1 = self._to_px(self.x1, self.y1)
        p2 = self._to_px(self.x2, self.y2)
        p0 = self._to_px(0, 0)
        p3 = self._to_px(1, 1)
        cr.set_source_rgba(r, g, b, 0.30)
        cr.set_line_width(1.2)
        cr.move_to(*p0); cr.line_to(*p1); cr.stroke()
        cr.move_to(*p3); cr.line_to(*p2); cr.stroke()

        # Bezier curve
        ar, ag, ab = _accent_rgb()
        cr.set_source_rgba(ar, ag, ab, 1.0)
        cr.set_line_width(2.5)
        cr.move_to(*p0)
        steps = 80
        for i in range(1, steps + 1):
            t = i / steps
            bx = _cubic(t, self.x1, self.x2)
            by = _cubic(t, self.y1, self.y2)
            cr.line_to(*self._to_px(bx, by))
        cr.stroke()

        # Handle circles
        for pt_id, px, py in [("p1", p1[0], p1[1]), ("p2", p2[0], p2[1])]:
            if self._dragging == pt_id:
                cr.set_source_rgba(1.0, 1.0, 1.0, 0.95)
            else:
                cr.set_source_rgba(ar, ag, ab, 1.0)
            cr.arc(px, py, _HANDLE_R, 0, 2 * math.pi)
            cr.fill()
            cr.set_source_rgba(r, g, b, 0.05)
            cr.arc(px, py, _HANDLE_R - 3, 0, 2 * math.pi)
            cr.fill()
            cr.set_source_rgba(ar, ag, ab, 1.0)
            cr.arc(px, py, _HANDLE_R - 5, 0, 2 * math.pi)
            cr.fill()


# ── Preview strip ─────────────────────────────────────────────────────────────

class BezierPreview(Gtk.DrawingArea):
    """Animated dot moving along a track with the current easing."""

    _SPEED = 0.011
    _PAUSE_US = 800_000

    def __init__(self) -> None:
        super().__init__()
        self.x1, self.y1 = 0.25, 0.10
        self.x2, self.y2 = 0.25, 1.00
        self._progress = 0.0
        self._pause_until = 0
        self._tick_id = 0
        self._ease_min = 0.0
        self._ease_max = 1.0
        self.set_content_height(36)
        self.set_draw_func(self._draw)

    def start(self) -> None:
        if self._tick_id == 0:
            self._tick_id = self.add_tick_callback(self._tick)

    def stop(self) -> None:
        if self._tick_id:
            self.remove_tick_callback(self._tick_id)
            self._tick_id = 0

    def set_points(self, x1: float, y1: float, x2: float, y2: float) -> None:
        self.x1, self.y1, self.x2, self.y2 = x1, y1, x2, y2
        samples = [ease(i / 100, x1, y1, x2, y2) for i in range(101)]
        self._ease_min = min(0.0, min(samples))
        self._ease_max = max(1.0, max(samples))
        self.queue_draw()

    def _tick(self, _widget, clock) -> bool:
        now = clock.get_frame_time()
        if self._pause_until:
            if now < self._pause_until:
                return GLib.SOURCE_CONTINUE
            self._pause_until = 0
            self._progress = 0.0
            self.queue_draw()
            return GLib.SOURCE_CONTINUE
        self._progress += self._SPEED
        if self._progress >= 1.0:
            self._progress = 1.0
            self._pause_until = now + self._PAUSE_US
        self.queue_draw()
        return GLib.SOURCE_CONTINUE

    def _draw(self, _area, cr, width: int, height: int) -> None:  # type: ignore[override]
        fg = self.get_color()
        r, g, b = fg.red, fg.green, fg.blue
        dot_r = 6
        pad = dot_r + 4
        span = max(0.001, self._ease_max - self._ease_min)
        usable = width - 2 * pad

        def val_x(v):
            return pad + (v - self._ease_min) / span * usable

        track_y = height / 2
        cr.set_source_rgba(r, g, b, 0.14)
        cr.set_line_width(2)
        cr.move_to(val_x(0), track_y)
        cr.line_to(val_x(1), track_y)
        cr.stroke()

        eased = ease(self._progress, self.x1, self.y1, self.x2, self.y2)
        ar, ag, ab = _accent_rgb()
        cr.set_source_rgba(ar, ag, ab, 1.0)
        cr.arc(val_x(eased), track_y, dot_r, 0, 2 * math.pi)
        cr.fill()


# ── Main editor widget ────────────────────────────────────────────────────────

class BezierEditorWidget(Gtk.Box):
    """Canvas + preview + controls for editing and saving bezier curves."""

    def __init__(self) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self._block_spin = False

        self._canvas = BezierCanvas(
            on_change=self._canvas_changed,
            on_drag_end=self._update_actions,
        )
        self._canvas.set_halign(Gtk.Align.CENTER)

        frame = Gtk.Frame()
        frame.set_child(self._canvas)
        frame.set_halign(Gtk.Align.CENTER)
        self.append(frame)

        hint = Gtk.Label(label="Drag the control points to edit the curve")
        hint.add_css_class("dim-label")
        hint.add_css_class("caption")
        hint.set_halign(Gtk.Align.CENTER)
        self.append(hint)

        self._preview = BezierPreview()
        self._preview.set_hexpand(True)
        self.append(self._preview)

        # Preset dropdown
        preset_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        preset_row.set_halign(Gtk.Align.CENTER)
        preset_lbl = Gtk.Label(label="Preset")
        preset_lbl.add_css_class("dim-label")
        preset_row.append(preset_lbl)
        self._preset_dd = Gtk.DropDown()
        self._refresh_preset_model()
        self._preset_dd.connect("notify::selected", self._preset_selected)
        preset_row.append(self._preset_dd)
        self.append(preset_row)

        # Numeric inputs
        inputs_grp = Adw.PreferencesGroup(title="Control Points")

        def _spin(val, lo, hi):
            adj = Gtk.Adjustment(value=val, lower=lo, upper=hi,
                                 step_increment=0.01, page_increment=0.1)
            btn = Gtk.SpinButton(adjustment=adj, digits=3, width_chars=6)
            btn.set_valign(Gtk.Align.CENTER)
            btn.connect("value-changed", self._spin_changed)
            return btn

        def _point_row(label, xv, yv):
            row = Adw.ActionRow(title=label)
            xl = Gtk.Label(label="X"); xl.add_css_class("dim-label"); xl.set_valign(Gtk.Align.CENTER); xl.set_margin_end(4)
            yl = Gtk.Label(label="Y"); yl.add_css_class("dim-label"); yl.set_valign(Gtk.Align.CENTER); yl.set_margin_start(12); yl.set_margin_end(4)
            sx = _spin(xv, 0.0, 1.0)
            sy = _spin(yv, -10.0, 10.0)
            row.add_suffix(xl); row.add_suffix(sx)
            row.add_suffix(yl); row.add_suffix(sy)
            return row, sx, sy

        row1, self._sx1, self._sy1 = _point_row("Point 1", self._canvas.x1, self._canvas.y1)
        row2, self._sx2, self._sy2 = _point_row("Point 2", self._canvas.x2, self._canvas.y2)
        inputs_grp.add(row1)
        inputs_grp.add(row2)
        self.append(inputs_grp)

        # Name entry + action buttons
        name_row = Adw.EntryRow(title="Curve Name")
        name_row.set_text(_store().next_name())
        self._name_row = name_row
        grp = Adw.PreferencesGroup()
        grp.add(name_row)
        self.append(grp)

        # Action bar
        bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        bar.set_halign(Gtk.Align.CENTER)
        bar.set_margin_top(4)

        self._revert_btn = Gtk.Button(label="Revert")
        self._revert_btn.add_css_class("flat")
        self._revert_btn.connect("clicked", lambda _: self._do_revert())
        bar.append(self._revert_btn)

        self._save_btn = Gtk.Button(label="Save curve")
        self._save_btn.add_css_class("pill")
        self._save_btn.add_css_class("suggested-action")
        self._save_btn.connect("clicked", lambda _: self._do_save())
        bar.append(self._save_btn)

        self._apply_btn = Gtk.Button(label="Apply to Hyprland")
        self._apply_btn.add_css_class("pill")
        self._apply_btn.connect("clicked", lambda _: self._do_apply())
        bar.append(self._apply_btn)

        self._delete_btn = Gtk.Button(icon_name="user-trash-symbolic")
        self._delete_btn.add_css_class("flat")
        self._delete_btn.add_css_class("error")
        self._delete_btn.set_tooltip_text("Delete custom curve")
        self._delete_btn.connect("clicked", lambda _: self._do_delete())
        bar.append(self._delete_btn)

        self.append(bar)

        # Toast target (filled in by dialog)
        self._toast_ov: Adw.ToastOverlay | None = None

        # Initial state
        self._base_name = list(BUILTIN_PRESETS)[0]
        self._base_pts = BUILTIN_PRESETS[self._base_name]
        self._sync_preview()
        self._preview.start()
        self._update_actions()

    # ── State helpers ──────────────────────────────────────────────────────────

    def _cur_pts(self) -> tuple[float, float, float, float]:
        return self._canvas.x1, self._canvas.y1, self._canvas.x2, self._canvas.y2

    def _is_modified(self) -> bool:
        return self._cur_pts() != self._base_pts

    def _is_user_curve(self) -> bool:
        return self._base_name in _store().user_names()

    def _update_actions(self) -> None:
        modified = self._is_modified()
        user = self._is_user_curve()
        self._revert_btn.set_visible(modified)
        self._save_btn.set_visible(modified or not user)
        self._delete_btn.set_visible(user)
        # Apply button always visible
        self._apply_btn.set_visible(True)

    # ── Model change handlers ──────────────────────────────────────────────────

    def _canvas_changed(self, x1, y1, x2, y2) -> None:
        self._block_spin = True
        self._sx1.set_value(x1); self._sy1.set_value(y1)
        self._sx2.set_value(x2); self._sy2.set_value(y2)
        self._block_spin = False
        self._sync_preview()
        self._update_actions()

    def _spin_changed(self, _btn) -> None:
        if self._block_spin:
            return
        x1 = round(self._sx1.get_value(), 3)
        y1 = round(self._sy1.get_value(), 3)
        x2 = round(self._sx2.get_value(), 3)
        y2 = round(self._sy2.get_value(), 3)
        self._canvas.set_points(x1, y1, x2, y2)
        self._sync_preview()
        self._update_actions()

    def _preset_selected(self, dd: Gtk.DropDown, _pspec) -> None:
        idx = dd.get_selected()
        names = _store().all_names()
        if 0 <= idx < len(names):
            name = names[idx]
            pts = _store().get_points(name)
            if pts:
                self._base_name = name
                self._base_pts = pts
                self._canvas.set_points(*pts)
                self._block_spin = True
                self._sx1.set_value(pts[0]); self._sy1.set_value(pts[1])
                self._sx2.set_value(pts[2]); self._sy2.set_value(pts[3])
                self._block_spin = False
                self._sync_preview()
                self._update_actions()
                # Pre-fill the name entry with this curve's name
                if _store().is_builtin(name):
                    self._name_row.set_text(_store().next_name())
                else:
                    self._name_row.set_text(name)

    def _sync_preview(self) -> None:
        pts = self._cur_pts()
        self._preview.set_points(*pts)

    # ── Actions ────────────────────────────────────────────────────────────────

    def _do_revert(self) -> None:
        self._canvas.set_points(*self._base_pts)
        self._block_spin = True
        self._sx1.set_value(self._base_pts[0]); self._sy1.set_value(self._base_pts[1])
        self._sx2.set_value(self._base_pts[2]); self._sy2.set_value(self._base_pts[3])
        self._block_spin = False
        self._sync_preview()
        self._update_actions()

    def _do_save(self) -> None:
        name = self._name_row.get_text().strip()
        if not name:
            self._toast("Enter a curve name first")
            return
        pts = self._cur_pts()
        _store().save(name, pts)
        _invalidate_store()
        self._base_name = name
        self._base_pts = pts
        self._refresh_preset_model()
        self._select_preset(name)
        self._update_actions()
        self._toast(f'Saved curve "{name}"')

    def _do_apply(self) -> None:
        name = self._name_row.get_text().strip() or "cloudCenterBezier"
        pts = self._cur_pts()
        # Save to library if it's a user name
        if not _store().is_builtin(name):
            _store().save(name, pts)
        # Apply via hyprctl
        bezier_str = f"{name},{pts[0]},{pts[1]},{pts[2]},{pts[3]}"
        threading.Thread(target=self._apply_worker, args=(name, bezier_str), daemon=True).start()

    def _apply_worker(self, name: str, bezier_str: str) -> None:
        try:
            bezier_run = subprocess.run(
                ["hyprctl", "keyword", "animations:bezier", bezier_str],
                capture_output=True, text=True, timeout=5,
            )
            if bezier_run.returncode != 0:
                err = (bezier_run.stderr or bezier_run.stdout or "hyprctl failed").strip()
                GLib.idle_add(self._toast, f"Apply failed: {err}")
                return

            # Make the applied curve active for the main windows animation profile.
            try:
                from lib import utility
                speed = int(float(utility.load_setting("hypr/anim_speed", 4)))
            except Exception:
                speed = 4
            anim_value = f"windows,1,{speed},{name}"

            anim_run = subprocess.run(
                ["hyprctl", "keyword", "animations:animation", anim_value],
                capture_output=True, text=True, timeout=5,
            )
            if anim_run.returncode != 0:
                err = (anim_run.stderr or anim_run.stdout or "hyprctl failed").strip()
                GLib.idle_add(self._toast, f"Curve saved, but activation failed: {err}")
                return

            # Persist both keywords via the shared persistence script.
            persist_script = Path(__file__).resolve().parent.parent / "hypr_persist.sh"
            if persist_script.exists():
                subprocess.run(
                    [str(persist_script), "animations:bezier", bezier_str],
                    capture_output=True, text=True, timeout=5,
                )
                subprocess.run(
                    [str(persist_script), "animations:animation", anim_value],
                    capture_output=True, text=True, timeout=5,
                )

            GLib.idle_add(self._toast, f'Applied "{name}" to Hyprland windows animation')
        except Exception as exc:
            GLib.idle_add(self._toast, f"Apply failed: {exc}")

    def _do_delete(self) -> None:
        name = self._base_name
        if not _store().is_builtin(name):
            _store().delete(name)
            _invalidate_store()
            self._refresh_preset_model()
            # Fall back to first preset
            first = list(BUILTIN_PRESETS)[0]
            self._base_name = first
            self._base_pts = BUILTIN_PRESETS[first]
            self._canvas.set_points(*self._base_pts)
            self._sync_preview()
            self._preset_dd.set_selected(0)
            self._update_actions()
            self._toast(f'Deleted "{name}"')

    # ── Preset dropdown management ────────────────────────────────────────────

    def _refresh_preset_model(self) -> None:
        store = _store()
        labels: list[str] = []
        user_set = set(store.user_names())
        for n in store.all_names():
            labels.append(f"★ {n}" if n in user_set else n)
        self._preset_dd.set_model(Gtk.StringList.new(labels))

    def _select_preset(self, name: str) -> None:
        names = _store().all_names()
        if name in names:
            self._preset_dd.set_selected(names.index(name))

    def cleanup(self) -> None:
        self._preview.stop()

    def _toast(self, msg: str) -> bool:
        from lib.utility import toast as _toast_fn
        if self._toast_ov:
            _toast_fn(self._toast_ov, msg)
        else:
            log.info("Bezier editor: %s", msg)
        return GLib.SOURCE_REMOVE


# ── Dialog wrapper ────────────────────────────────────────────────────────────

class BezierEditorDialog(Adw.Dialog):
    """Adw.Dialog wrapping BezierEditorWidget."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__()
        self.set_title("Bezier Curve Editor")
        self.set_content_width(360)
        self.set_follows_content_size(True)

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())

        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_propagate_natural_height(True)
        scroll.set_propagate_natural_width(True)

        self._editor = BezierEditorWidget()
        self._editor._toast_ov = toast_overlay
        self._editor.set_margin_top(12)
        self._editor.set_margin_bottom(24)
        self._editor.set_margin_start(12)
        self._editor.set_margin_end(12)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(400)
        clamp.set_child(self._editor)

        scroll.set_child(clamp)
        toolbar.set_content(scroll)
        self.set_child(toolbar)
        self.connect("closed", lambda _: self._editor.cleanup())
