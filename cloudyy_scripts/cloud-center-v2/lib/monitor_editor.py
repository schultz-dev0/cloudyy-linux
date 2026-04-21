"""Cloud Center — Monitor Editor page.

Two-panel layout mirroring the keybind/wifi pages:
  Left:  list of connected monitors (from hyprctl monitors -j)
  Right: per-monitor settings editor

Writes to ~/.config/hypr/user-configs/user_monitors.conf
and reloads Hyprland on apply.
"""
from __future__ import annotations

import math
import json
import logging
import os
import re
import subprocess
import tempfile
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from gi.repository import Adw, GLib, Gtk, Pango

log = logging.getLogger(__name__)

HYPR_DIR       = Path.home() / ".config" / "hypr"
MONITORS_CONF  = HYPR_DIR / "user-configs" / "user_monitors.conf"

TRANSFORM_LABELS = [
    (0, "Normal"),
    (1, "90°"),
    (2, "180°"),
    (3, "270°"),
    (4, "Flipped"),
    (5, "Flipped 90°"),
    (6, "Flipped 180°"),
    (7, "Flipped 270°"),
]

HEADLESS_DEFAULT_MODES = [
    "3840x2160@60.00Hz",
    "2560x1440@60.00Hz",
    "1920x1080@60.00Hz",
    "1600x900@60.00Hz",
    "1280x720@60.00Hz",
]


# ── Data ──────────────────────────────────────────────────────────────────────

@dataclass
class MonitorInfo:
    name:            str
    description:     str
    make:            str
    model:           str
    width:           int
    height:          int
    refresh_rate:    float
    x:               int
    y:               int
    scale:           float
    transform:       int
    disabled:        bool
    mirror_of:       str
    focused:         bool
    available_modes: list[str] = field(default_factory=list)
    assigned_workspaces: list[str] = field(default_factory=list)

    @property
    def current_mode_str(self) -> str:
        """e.g. '2560x1440@155.00Hz'"""
        return f"{self.width}x{self.height}@{self.refresh_rate:.2f}Hz"

    @property
    def display_name(self) -> str:
        return self.model or self.description or self.name


def _normalise_mode_label(raw_mode: object) -> str:
    """Convert a mode value to a canonical '<w>x<h>@<hz>Hz' label when possible."""
    if raw_mode is None:
        return ""

    text = str(raw_mode).strip()
    if not text:
        return ""

    match = re.search(r"(\d+x\d+)\s*@\s*([\d.]+)", text)
    if not match:
        return text

    res = match.group(1)
    try:
        hz = float(match.group(2))
    except ValueError:
        return f"{res}@{match.group(2)}Hz"
    return f"{res}@{hz:.2f}Hz"


def _mode_is_usable(mode: str) -> bool:
    norm = _normalise_mode_label(mode)
    m = re.match(r"^(\d+)x(\d+)@([\d.]+)", norm)
    if not m:
        return False
    try:
        return int(m.group(1)) > 0 and int(m.group(2)) > 0 and float(m.group(3)) > 0.0
    except ValueError:
        return False


def _is_headless_name(name: str) -> bool:
    return "headless" in name.lower()


def _extract_available_modes(payload: dict, current_mode: str) -> list[str]:
    """Read available modes from hyprctl payload across multiple possible shapes."""
    raw_modes = payload.get("availableModes") or payload.get("modes") or []
    out: list[str] = []
    seen: set[str] = set()

    def add_mode(label: str) -> None:
        mode = _normalise_mode_label(label)
        if not mode or mode in seen:
            return
        seen.add(mode)
        out.append(mode)

    for entry in raw_modes:
        if isinstance(entry, str):
            add_mode(entry)
            continue

        if isinstance(entry, dict):
            mode_text = entry.get("mode")
            if mode_text:
                add_mode(str(mode_text))
                continue

            width = entry.get("width")
            height = entry.get("height")
            refresh = (
                entry.get("refreshRate")
                or entry.get("refresh")
                or entry.get("hz")
            )
            if width and height and refresh:
                try:
                    add_mode(f"{int(width)}x{int(height)}@{float(refresh):.2f}Hz")
                    continue
                except (TypeError, ValueError):
                    pass

            add_mode(str(entry))

    if _mode_is_usable(current_mode):
        add_mode(current_mode)

    if not out and _is_headless_name(str(payload.get("name", ""))):
        for mode in HEADLESS_DEFAULT_MODES:
            add_mode(mode)
    return out


def _mode_sort_key(mode: str) -> tuple[int, int, float]:
    """Sort modes by width, then height, then refresh (descending)."""
    norm = _normalise_mode_label(mode)
    match = re.match(r"^(\d+)x(\d+)@([\d.]+)", norm)
    if not match:
        return (0, 0, 0.0)
    try:
        return (int(match.group(1)), int(match.group(2)), float(match.group(3)))
    except ValueError:
        return (0, 0, 0.0)


def _fetch_modes_from_monitors_all() -> dict[str, list[str]]:
    """Fallback source for monitor modes using `hyprctl monitors all -j`."""
    try:
        out = subprocess.run(
            ["hyprctl", "monitors", "all", "-j"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        payload = json.loads(out.stdout)
    except Exception as exc:
        log.debug("hyprctl monitors all failed: %s", exc)
        return {}

    result: dict[str, list[str]] = {}
    for mon in payload if isinstance(payload, list) else []:
        name = str(mon.get("name", "")).strip()
        if not name:
            continue
        current_mode = _normalise_mode_label(
            f"{mon.get('width', 0)}x{mon.get('height', 0)}@{mon.get('refreshRate', 60.0)}"
        )
        modes = _extract_available_modes(mon, current_mode)
        if modes:
            modes.sort(key=_mode_sort_key, reverse=True)
            result[name] = modes
    return result


def _fetch_monitors() -> list[MonitorInfo]:
    try:
        out = subprocess.run(
            ["hyprctl", "monitors", "-j"],
            capture_output=True, text=True, timeout=5,
        )
        data = json.loads(out.stdout)
    except Exception as e:
        log.warning("hyprctl monitors failed: %s", e)
        return []

    # Skip `monitors all` when a HEADLESS output is active — that IPC call can
    # crash Hyprland when wayvnc holds the HEADLESS output (e.g. hypr-display).
    # HEADLESS monitors already have HEADLESS_DEFAULT_MODES as their fallback.
    has_headless = any(_is_headless_name(str(m.get("name", ""))) for m in data)
    fallback_modes = {} if has_headless else _fetch_modes_from_monitors_all()

    # Parse config to get workspace assignments
    _, config_workspaces = _parse_conf()

    monitors = []
    for m in data:
        name = m.get("name", "")
        current_mode = _normalise_mode_label(
            f"{m.get('width', 0)}x{m.get('height', 0)}@{m.get('refreshRate', 60.0)}"
        )
        modes = _extract_available_modes(m, current_mode)
        if name in fallback_modes:
            merged = {mode: None for mode in modes}
            for mode in fallback_modes[name]:
                merged.setdefault(mode, None)
            modes = list(merged.keys())

        modes.sort(key=_mode_sort_key, reverse=True)

        monitors.append(MonitorInfo(
            name          = name,
            description   = m.get("description", ""),
            make          = m.get("make", ""),
            model         = m.get("model", ""),
            width         = m.get("width", 0),
            height        = m.get("height", 0),
            refresh_rate  = m.get("refreshRate", 60.0),
            x             = m.get("x", 0),
            y             = m.get("y", 0),
            scale         = m.get("scale", 1.0),
            transform     = m.get("transform", 0),
            disabled      = m.get("disabled", False),
            mirror_of     = m.get("mirrorOf", "") or "",
            focused       = m.get("focused", False),
            available_modes = modes,
            assigned_workspaces = config_workspaces.get(name, []),
        ))
    return monitors



class DisplayLayoutPreview(Gtk.Box):
    """Simple monitor arrangement canvas with drag-and-drop positioning."""

    SNAP_THRESHOLD_PX = 48

    def __init__(
        self,
        monitors: list[MonitorInfo],
        on_monitor_selected,
        on_monitor_moved,
    ) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.set_hexpand(True)

        self._on_monitor_selected = on_monitor_selected
        self._on_monitor_moved = on_monitor_moved

        self._positions: dict[str, tuple[int, int]] = {
            m.name: (m.x, m.y) for m in monitors
        }
        self._sizes: dict[str, tuple[int, int]] = {
            m.name: (max(64, int(m.width)), max(64, int(m.height))) for m in monitors
        }
        self._enabled: dict[str, bool] = {m.name: not m.disabled for m in monitors}
        self._labels: dict[str, str] = {m.name: m.name for m in monitors}
        self._workspaces: dict[str, list[str]] = {m.name: getattr(m, "assigned_workspaces", []) for m in monitors}
        self._order: list[str] = [m.name for m in monitors]

        self._selected_name = monitors[0].name if monitors else ""
        self._drag_name = ""
        self._drag_start_pos = (0, 0)
        self._drag_scale = 1.0

        self._area = Gtk.DrawingArea()
        self._area.set_content_width(620)
        self._area.set_content_height(280)
        self._area.set_hexpand(True)
        self._area.set_vexpand(False)
        self._area.set_draw_func(self._draw)
        self.append(self._area)

        click = Gtk.GestureClick.new()
        click.connect("pressed", self._on_click_pressed)
        self._area.add_controller(click)

        drag = Gtk.GestureDrag.new()
        drag.connect("drag-begin", self._on_drag_begin)
        drag.connect("drag-update", self._on_drag_update)
        drag.connect("drag-end", self._on_drag_end)
        self._area.add_controller(drag)

    def set_selected(self, name: str) -> None:
        if name in self._positions:
            self._selected_name = name
            self._area.queue_draw()

    def update_monitor_position(self, name: str, x: int, y: int) -> None:
        if name not in self._positions:
            return
        self._positions[name] = (x, y)
        self._area.queue_draw()

    def update_workspaces(self, name: str, workspaces: list[str]) -> None:
        if name not in self._workspaces:
            return
        self._workspaces[name] = list(workspaces)
        self._area.queue_draw()

    def _global_bounds(self) -> tuple[float, float, float, float]:
        if not self._order:
            return (0.0, 0.0, 1.0, 1.0)

        min_x = math.inf
        min_y = math.inf
        max_x = -math.inf
        max_y = -math.inf

        for name in self._order:
            x, y = self._positions.get(name, (0, 0))
            w, h = self._sizes.get(name, (1920, 1080))
            min_x = min(min_x, x)
            min_y = min(min_y, y)
            max_x = max(max_x, x + w)
            max_y = max(max_y, y + h)

        if not math.isfinite(min_x) or not math.isfinite(min_y):
            return (0.0, 0.0, 1.0, 1.0)

        return (min_x, min_y, max_x, max_y)

    def _layout_transform(self, width: int, height: int) -> tuple[float, float, float]:
        min_x, min_y, max_x, max_y = self._global_bounds()
        world_w = max(1.0, max_x - min_x)
        world_h = max(1.0, max_y - min_y)

        pad = 18.0
        avail_w = max(1.0, width - pad * 2)
        avail_h = max(1.0, height - pad * 2)
        scale = min(avail_w / world_w, avail_h / world_h)
        scale = max(0.05, min(0.35, scale))

        off_x = (width - world_w * scale) / 2.0
        off_y = (height - world_h * scale) / 2.0
        return (scale, off_x - min_x * scale, off_y - min_y * scale)

    def _world_to_canvas(self, x: float, y: float, scale: float, ox: float, oy: float) -> tuple[float, float]:
        return (x * scale + ox, y * scale + oy)

    def _canvas_to_world_delta(self, dx: float, dy: float, scale: float) -> tuple[int, int]:
        if scale <= 0:
            return (0, 0)
        return (int(round(dx / scale)), int(round(dy / scale)))

    def _hit_test(self, x: float, y: float, width: int, height: int) -> str:
        scale, ox, oy = self._layout_transform(width, height)
        for name in reversed(self._order):
            mx, my = self._positions.get(name, (0, 0))
            mw, mh = self._sizes.get(name, (1920, 1080))
            cx, cy = self._world_to_canvas(mx, my, scale, ox, oy)
            cw = mw * scale
            ch = mh * scale
            if cx <= x <= cx + cw and cy <= y <= cy + ch:
                return name
        return ""

    def _on_click_pressed(self, _gesture: Gtk.GestureClick, _n: int, x: float, y: float) -> None:
        width = self._area.get_allocated_width()
        height = self._area.get_allocated_height()
        hit = self._hit_test(x, y, width, height)
        if not hit:
            return
        self._selected_name = hit
        self._area.queue_draw()
        self._on_monitor_selected(hit)

    def _on_drag_begin(self, _gesture: Gtk.GestureDrag, x: float, y: float) -> None:
        width = self._area.get_allocated_width()
        height = self._area.get_allocated_height()
        hit = self._hit_test(x, y, width, height)
        if not hit:
            self._drag_name = ""
            return

        self._selected_name = hit
        self._drag_name = hit
        self._drag_start_pos = self._positions.get(hit, (0, 0))
        self._drag_scale, _, _ = self._layout_transform(width, height)
        self._on_monitor_selected(hit)
        self._area.queue_draw()

    def _on_drag_update(self, _gesture: Gtk.GestureDrag, offset_x: float, offset_y: float) -> None:
        if not self._drag_name:
            return

        dx, dy = self._canvas_to_world_delta(offset_x, offset_y, self._drag_scale)
        nx = self._drag_start_pos[0] + dx
        ny = self._drag_start_pos[1] + dy
        nx, ny = self._snap_position(self._drag_name, nx, ny)
        self._positions[self._drag_name] = (nx, ny)
        self._area.queue_draw()
        self._on_monitor_moved(self._drag_name, nx, ny)

    def _on_drag_end(self, _gesture: Gtk.GestureDrag, _offset_x: float, _offset_y: float) -> None:
        self._drag_name = ""

    def _snap_axis(self, value: int, candidates: list[int], threshold: int) -> int:
        """Return nearest candidate if within threshold; else return original value."""
        best = value
        best_dist = threshold + 1
        for candidate in candidates:
            dist = abs(candidate - value)
            if dist < best_dist:
                best = candidate
                best_dist = dist
        return best if best_dist <= threshold else value

    def _snap_position(self, moving_name: str, x: int, y: int) -> tuple[int, int]:
        """Snap monitor to nearby edges/corners of other monitors and to origin."""
        mw, mh = self._sizes.get(moving_name, (1920, 1080))

        x_candidates = [0]
        y_candidates = [0]

        for other_name in self._order:
            if other_name == moving_name:
                continue

            ox, oy = self._positions.get(other_name, (0, 0))
            ow, oh = self._sizes.get(other_name, (1920, 1080))

            # Horizontal edge alignments:
            # moving left/right to other's left/right
            x_candidates.extend([
                ox,
                ox + ow,
                ox - mw,
                ox + ow - mw,
            ])

            # Vertical edge alignments:
            # moving top/bottom to other's top/bottom
            y_candidates.extend([
                oy,
                oy + oh,
                oy - mh,
                oy + oh - mh,
            ])

        snapped_x = self._snap_axis(x, x_candidates, self.SNAP_THRESHOLD_PX)
        snapped_y = self._snap_axis(y, y_candidates, self.SNAP_THRESHOLD_PX)
        return (snapped_x, snapped_y)

    def _draw(self, _area: Gtk.DrawingArea, cr, width: int, height: int) -> None:
        cr.set_source_rgb(0.12, 0.13, 0.16)
        cr.rectangle(0, 0, width, height)
        cr.fill()

        scale, ox, oy = self._layout_transform(width, height)
        for name in self._order:
            x, y = self._positions.get(name, (0, 0))
            w, h = self._sizes.get(name, (1920, 1080))
            enabled = self._enabled.get(name, True)
            selected = (name == self._selected_name)

            cx, cy = self._world_to_canvas(x, y, scale, ox, oy)
            cw = w * scale
            ch = h * scale

            if enabled:
                cr.set_source_rgba(0.17, 0.35, 0.57, 0.95)
            else:
                cr.set_source_rgba(0.26, 0.26, 0.28, 0.85)

            cr.rectangle(cx, cy, cw, ch)
            cr.fill_preserve()

            if selected:
                cr.set_source_rgba(0.98, 0.98, 0.98, 0.95)
                cr.set_line_width(3.0)
            else:
                cr.set_source_rgba(0.82, 0.85, 0.89, 0.9)
                cr.set_line_width(1.5)
            cr.stroke()

            label = self._labels.get(name, name)
            cr.select_font_face("Sans", 0, 0)
            cr.set_font_size(12)
            ext = cr.text_extents(label)
            tx = cx + max(8.0, (cw - ext.width) / 2.0)
            ty = cy + max(18.0, (ch + ext.height) / 2.0)
            cr.set_source_rgba(1.0, 1.0, 1.0, 0.95)
            cr.move_to(tx, ty)
            cr.show_text(label)

            # Draw workspaces
            ws_list = self._workspaces.get(name, [])
            if ws_list:
                ws_text = ", ".join(ws_list)
                cr.set_font_size(10)
                ext_ws = cr.text_extents(ws_text)
                twx = cx + max(4.0, (cw - ext_ws.width) / 2.0)
                twy = ty + 16
                if twy < cy + ch - 4:
                    cr.set_source_rgba(1.0, 1.0, 1.0, 0.7)
                    cr.move_to(twx, twy)
                    cr.show_text(ws_text)


# ── Config I/O ────────────────────────────────────────────────────────────────

def _parse_conf() -> tuple[dict[str, str], dict[str, list[str]]]:
    """Return ({monitor_name: raw_line}, {monitor_name: [workspace_ids]}) from user_monitors.conf."""
    monitors: dict[str, str] = {}
    workspaces: dict[str, list[str]] = {}
    if not MONITORS_CONF.exists():
        return monitors, workspaces
    try:
        for line in MONITORS_CONF.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("monitor="):
                # monitor=NAME,...
                rest = stripped[len("monitor="):]
                name = rest.split(",")[0].strip()
                if name:
                    monitors[name] = stripped
            elif stripped.startswith("workspace="):
                # workspace=ID,monitor:NAME
                # Also handle optional workspace rules like workspace=ID,monitor:NAME,default:true
                match = re.match(r"workspace\s*=\s*(.+?)\s*,\s*monitor:(.+)", stripped)
                if match:
                    ws_id = match.group(1).strip()
                    mon_part = match.group(2).split(",")[0].strip()
                    workspaces.setdefault(mon_part, []).append(ws_id)
    except OSError:
        pass
    return monitors, workspaces


def _build_monitor_line(
    name: str,
    mode: str,           # e.g. "2560x1440@155.00Hz" → strip Hz for config
    pos_x: int,
    pos_y: int,
    scale: float,
    transform: int,
    enabled: bool,
    mirror_of: str,
) -> str:
    if not enabled:
        return f"monitor={name},disable"

    # Strip trailing "Hz" — Hyprland config uses numeric refresh without unit
    mode_conf = re.sub(r"Hz$", "", mode, flags=re.IGNORECASE)

    scale_str = f"{scale:.4g}"          # 1, 1.5, 2, etc. — no trailing zeros
    line = f"monitor={name},{mode_conf},{pos_x}x{pos_y},{scale_str}"

    if transform != 0:
        line += f",transform,{transform}"
    if mirror_of and mirror_of.lower() not in ("", "none"):
        line += f",mirror,{mirror_of}"

    return line


def _write_monitor_line(name: str, line: str, workspaces: list[str]) -> None:
    """Insert or replace the monitor= and workspace= lines for `name` in user_monitors.conf."""
    MONITORS_CONF.parent.mkdir(parents=True, exist_ok=True)

    header = (
        "# ─────────────────────────────────────────────────────────────────\n"
        "# Hyprland monitor configuration — managed by Cloud Center\n"
        "# ─────────────────────────────────────────────────────────────────\n"
        "\n"
    )

    if MONITORS_CONF.exists():
        existing = MONITORS_CONF.read_text(encoding="utf-8").splitlines(keepends=True)
    else:
        existing = header.splitlines(keepends=True)

    out_lines: list[str] = []
    replaced_monitor = False
    
    # Track workspaces assigned to THIS monitor to avoid re-adding
    current_ws_set = set(workspaces)

    for raw in existing:
        stripped = raw.strip()
        if stripped.startswith("monitor="):
            rest = stripped[len("monitor="):]
            existing_name = rest.split(",")[0].strip()
            if existing_name == name:
                if not replaced_monitor:
                    out_lines.append(line + "\n")
                    for ws in workspaces:
                        out_lines.append(f"workspace={ws},monitor:{name}\n")
                    replaced_monitor = True
                continue
        elif stripped.startswith("workspace="):
            # workspace=ID,monitor:MON_NAME
            match = re.search(r"workspace\s*=\s*(.+?)\s*,\s*monitor:(.+)$", stripped)
            if match:
                ws_id = match.group(1).strip()
                mon_part = match.group(2).split(",")[0].strip()
                
                # If this workspace is now assigned to our monitor, 
                # we skip the old line (even if it was for a different monitor) 
                # to ensure exclusivity.
                if ws_id in current_ws_set:
                    continue
                    
                # If this line was for OUR monitor but NOT in the new list, skip it
                if mon_part == name:
                    continue
        
        out_lines.append(raw if raw.endswith("\n") else raw + "\n")

    if not replaced_monitor:
        if not out_lines:
            out_lines = [l for l in header.splitlines(keepends=True)]
        out_lines.append(line + "\n")
        for ws in workspaces:
            out_lines.append(f"workspace={ws},monitor:{name}\n")

    tmp_fd, tmp_path = tempfile.mkstemp(dir=str(MONITORS_CONF.parent))
    with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
        f.writelines(out_lines)
        f.flush()
        os.fsync(f.fileno())
    Path(tmp_path).replace(MONITORS_CONF)

    # Ensure this user config is actually sourced by hyprland.conf.
    try:
        from lib import hcm
        hcm.ensure_user_config_sourced(MONITORS_CONF)
    except Exception as exc:
        log.warning("Could not ensure source for %s: %s", MONITORS_CONF, exc)

    log.info("Wrote monitor config for %s: %s (workspaces: %s)", name, line, workspaces)


def _apply_monitor_line(line: str) -> tuple[bool, str]:
    """Apply a monitor rule live via hyprctl without reloading the compositor."""
    if not line.startswith("monitor="):
        return False, "Invalid monitor rule"

    rule = line[len("monitor="):]
    try:
        result = subprocess.run(
            ["hyprctl", "keyword", "monitor", rule],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as exc:
        return False, str(exc)

    stdout = (result.stdout or "").strip()
    stderr = (result.stderr or "").strip()
    response = stdout or stderr
    lowered = response.lower()

    if result.returncode != 0:
        return False, response or f"hyprctl exited with status {result.returncode}"
    if lowered and "ok" not in lowered and any(token in lowered for token in ("error", "failed", "invalid")):
        return False, response
    return True, response or "ok"


# ── GTK Page ──────────────────────────────────────────────────────────────────

class MonitorEditorPage(Gtk.Box):
    """Two-panel monitor editor."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._toast_ov  = toast_overlay
        self._monitors: list[MonitorInfo] = []
        self._selected: Optional[MonitorInfo] = None
        self._layout_preview: Optional[DisplayLayoutPreview] = None
        self._updating_position_widgets = False
        self._custom_mode_row: Optional[Adw.EntryRow] = None

        self._build_ui()
        self.refresh()

    @staticmethod
    def _set_combo_strings(row: Adw.ComboRow, values: list[str]) -> None:
        row.set_model(Gtk.StringList.new(values))
        set_expression = getattr(row, "set_expression", None)
        prop_expr = getattr(Gtk, "PropertyExpression", None)
        str_obj = getattr(Gtk, "StringObject", None)
        if not callable(set_expression) or prop_expr is None or str_obj is None:
            return
        try:
            row.set_expression(prop_expr.new(str_obj, None, "string"))
        except Exception as exc:
            log.debug("ComboRow expression setup failed: %s", exc)

    # ── Build ─────────────────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        # ── Left panel ──────────────────────────────────────────────────────
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        left.set_size_request(260, -1)

        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        hdr.set_margin_start(12)
        hdr.set_margin_end(8)
        hdr.set_margin_top(10)
        hdr.set_margin_bottom(6)

        title = Gtk.Label(label="Monitors")
        title.add_css_class("heading")
        title.set_hexpand(True)
        title.set_xalign(0)

        self._count_lbl = Gtk.Label(label="")
        self._count_lbl.add_css_class("dim-label")
        self._count_lbl.add_css_class("caption")

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Rescan monitors")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        add_headless_btn = Gtk.Button(icon_name="list-add-symbolic")
        add_headless_btn.add_css_class("flat")
        add_headless_btn.set_tooltip_text("Create Headless Display")
        add_headless_btn.connect("clicked", self._on_add_headless_clicked)

        hdr.append(title)
        hdr.append(self._count_lbl)
        hdr.append(add_headless_btn)
        hdr.append(refresh_btn)
        left.append(hdr)
        left.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.add_css_class("navigation-sidebar")
        self._list.connect("row-selected", self._on_row_selected)

        scroll_l = Gtk.ScrolledWindow()
        scroll_l.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll_l.set_vexpand(True)
        scroll_l.set_child(self._list)
        left.append(scroll_l)

        # ── Right panel ─────────────────────────────────────────────────────
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        right.set_hexpand(True)

        # Placeholder shown when nothing selected
        self._placeholder = Adw.StatusPage(
            icon_name="video-display-symbolic",
            title="Select a monitor",
            description="Choose a display from the list to configure it.",
        )
        self._placeholder.set_vexpand(True)

        # Editor scroll area
        self._editor_scroll = Gtk.ScrolledWindow()
        self._editor_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._editor_scroll.set_vexpand(True)

        self._editor_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        self._editor_box.set_margin_top(16)
        self._editor_box.set_margin_bottom(16)
        self._editor_box.set_margin_start(16)
        self._editor_box.set_margin_end(16)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(700)
        clamp.set_child(self._editor_box)
        self._editor_scroll.set_child(clamp)

        self._stack = Gtk.Stack()
        self._stack.add_named(self._placeholder, "placeholder")
        self._stack.add_named(self._editor_scroll, "editor")
        self._stack.set_visible_child_name("placeholder")
        self._stack.set_vexpand(True)

        right.append(self._stack)

        self.append(left)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        self.append(right)

    def _build_editor(self, mon: MonitorInfo) -> None:
        """Populate the right-panel editor for a given monitor."""
        try:
            # Clear previous widgets
            while child := self._editor_box.get_first_child():
                self._editor_box.remove(child)

            # ── Monitor header ────────────────────────────────────────────────
            info_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            info_box.set_margin_bottom(4)

            name_lbl = Gtk.Label(label=mon.name)
            name_lbl.add_css_class("title-2")
            name_lbl.set_xalign(0)

            desc_lbl = Gtk.Label(label=mon.description)
            desc_lbl.add_css_class("dim-label")
            desc_lbl.set_xalign(0)
            desc_lbl.set_ellipsize(Pango.EllipsizeMode.END)

            info_box.append(name_lbl)
            info_box.append(desc_lbl)
            
            header_hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            header_hbox.append(info_box)
            
            if _is_headless_name(mon.name):
                remove_btn = Gtk.Button(icon_name="user-trash-symbolic")
                remove_btn.add_css_class("flat")
                remove_btn.add_css_class("destructive-action")
                remove_btn.set_tooltip_text("Remove this headless display")
                remove_btn.set_valign(Gtk.Align.START)
                remove_btn.connect("clicked", self._on_remove_headless_clicked, mon.name)
                header_hbox.append(Gtk.Box(hexpand=True))
                header_hbox.append(remove_btn)
                
            self._editor_box.append(header_hbox)

            # ── Enabled toggle ────────────────────────────────────────────────
            status_group = Adw.PreferencesGroup()
            self._enabled_row = Adw.SwitchRow(
                title="Enabled",
                subtitle="Turn this display on or off",
            )
            self._enabled_row.set_active(not mon.disabled)
            self._enabled_row.connect("notify::active", self._on_enabled_changed)
            status_group.add(self._enabled_row)
            self._editor_box.append(status_group)

            # ── Mode (resolution + refresh rate) ──────────────────────────────
            mode_group = Adw.PreferencesGroup(title="Display Mode")

            mode_labels = mon.available_modes if mon.available_modes else [mon.current_mode_str]
            mode_labels = [m for m in mode_labels if _mode_is_usable(m)]
            if not mode_labels and _is_headless_name(mon.name):
                mode_labels = list(HEADLESS_DEFAULT_MODES)
            if not mode_labels:
                mode_labels = ["1920x1080@60.00Hz"]
            self._mode_labels = mode_labels

            mode_row = Adw.ActionRow()
            mode_row.set_title("Resolution & Refresh Rate")

            # Explicit label widget keeps text visible on stacks where ActionRow title
            # rendering can be theme/version-sensitive.
            mode_label = Gtk.Label(label="Resolution & Refresh Rate")
            mode_label.set_xalign(0.0)
            mode_label.set_hexpand(True)
            mode_row.add_prefix(mode_label)

            self._mode_dropdown = Gtk.DropDown.new_from_strings(mode_labels)
            self._mode_dropdown.set_valign(Gtk.Align.CENTER)
            self._mode_dropdown.set_hexpand(False)
            mode_row.add_suffix(self._mode_dropdown)
            mode_row.set_activatable_widget(self._mode_dropdown)

            # Pre-select the current mode
            current = mon.current_mode_str
            for i, m in enumerate(mode_labels):
                if self._modes_match(m, current):
                    self._mode_dropdown.set_selected(i)
                    break

            mode_group.add(mode_row)

            # Some outputs (especially headless) may expose only one mode.
            # Allow manual override so users can still set a specific mode string.
            self._custom_mode_row = None
            if len(mode_labels) <= 1 or _is_headless_name(mon.name):
                self._custom_mode_row = Adw.EntryRow(
                    title="Custom Mode Override",
                )
                self._custom_mode_row.set_text("")
                set_apply_btn = getattr(self._custom_mode_row, "set_show_apply_button", None)
                if callable(set_apply_btn):
                    set_apply_btn(False)

                set_placeholder = getattr(self._custom_mode_row, "set_placeholder_text", None)
                if callable(set_placeholder):
                    set_placeholder("e.g. 1920x1080@60.00Hz")
                self._custom_mode_row.set_tooltip_text(
                    "Optional. If set, this value is used instead of the dropdown mode."
                )
                mode_group.add(self._custom_mode_row)

            # Scale
            self._scale_row = Adw.SpinRow(
                title="Scale",
                subtitle="Display scaling factor",
                adjustment=Gtk.Adjustment(
                    value=mon.scale,
                    lower=0.25, upper=4.0,
                    step_increment=0.25,
                    page_increment=0.5,
                ),
                digits=2,
            )
            mode_group.add(self._scale_row)

            # Transform / rotation
            self._transform_row = Adw.ComboRow(title="Rotation")
            self._set_combo_strings(self._transform_row, [label for _, label in TRANSFORM_LABELS])
            self._transform_row.set_selected(
                next((i for i, (v, _) in enumerate(TRANSFORM_LABELS) if v == mon.transform), 0)
            )
            mode_group.add(self._transform_row)
            self._editor_box.append(mode_group)

            # ── Visual arrangement preview ───────────────────────────────────
            layout_group = Adw.PreferencesGroup(
                title="Layout Preview",
                description="Drag displays to rearrange. Nearby edges/corners snap into alignment.",
            )

            self._layout_preview = DisplayLayoutPreview(
                monitors=self._monitors,
                on_monitor_selected=self._on_preview_selected,
                on_monitor_moved=self._on_preview_moved,
            )
            self._layout_preview.set_selected(mon.name)
            layout_group.add(self._layout_preview)
            self._editor_box.append(layout_group)

            # ── Position ──────────────────────────────────────────────────────
            pos_group = Adw.PreferencesGroup(
                title="Position",
                description="Top-left corner of this display in the global layout (pixels)",
            )

            self._pos_x_row = Adw.SpinRow(
                title="X",
                subtitle="Horizontal offset",
                adjustment=Gtk.Adjustment(
                    value=mon.x,
                    lower=-16384, upper=16384,
                    step_increment=1, page_increment=100,
                ),
                digits=0,
            )
            self._pos_x_row.connect("notify::value", self._on_position_spin_changed)
            pos_group.add(self._pos_x_row)

            self._pos_y_row = Adw.SpinRow(
                title="Y",
                subtitle="Vertical offset",
                adjustment=Gtk.Adjustment(
                    value=mon.y,
                    lower=-16384, upper=16384,
                    step_increment=1, page_increment=100,
                ),
                digits=0,
            )
            self._pos_y_row.connect("notify::value", self._on_position_spin_changed)
            pos_group.add(self._pos_y_row)
            self._editor_box.append(pos_group)

            # ── Mirror ────────────────────────────────────────────────────────
            mirror_group = Adw.PreferencesGroup(title="Mirror")
            other_names = ["(none)"] + [m.name for m in self._monitors if m.name != mon.name]
            self._mirror_row = Adw.ComboRow(title="Mirror of")
            self._set_combo_strings(self._mirror_row, other_names)

            current_mirror = mon.mirror_of if mon.mirror_of and mon.mirror_of.lower() != "none" else ""
            mirror_idx = 0
            if current_mirror:
                for i, n in enumerate(other_names):
                    if n == current_mirror:
                        mirror_idx = i
                        break
            self._mirror_row.set_selected(mirror_idx)
            mirror_group.add(self._mirror_row)
            self._editor_box.append(mirror_group)

            # ── Workspaces ───────────────────────────────────────────────────
            ws_group = Adw.PreferencesGroup(
                title="Workspaces",
                description="Assign workspaces to this monitor. Numeric 1-10 are quick-toggle.",
            )

            # Checkbox grid for 1-10
            ws_flow = Gtk.FlowBox()
            ws_flow.set_valign(Gtk.Align.START)
            ws_flow.set_max_children_per_line(5)
            ws_flow.set_min_children_per_line(5)
            ws_flow.set_selection_mode(Gtk.SelectionMode.NONE)
            ws_flow.set_column_spacing(12)
            ws_flow.set_row_spacing(8)
            ws_flow.set_margin_top(8)
            ws_flow.set_margin_bottom(8)
            ws_flow.set_margin_start(12)
            ws_flow.set_margin_end(12)

            self._ws_checks = {}
            for i in range(1, 11):
                ws_id = str(i)
                check = Gtk.CheckButton(label=ws_id)
                check.set_active(ws_id in mon.assigned_workspaces)
                check.connect("toggled", self._on_ws_toggled, ws_id)
                self._ws_checks[ws_id] = check
                ws_flow.insert(check, -1)

            ws_group.add(ws_flow)

            # Extras list (non-numeric 1-10)
            self._ws_extras_list = Gtk.ListBox()
            self._ws_extras_list.add_css_class("boxed-list")
            self._ws_extras_list.set_selection_mode(Gtk.SelectionMode.NONE)

            extras = [w for w in mon.assigned_workspaces if not (w.isdigit() and 1 <= int(w) <= 10)]
            for ws in extras:
                self._ws_extras_list.append(self._make_ws_row(ws))

            ws_group.add(self._ws_extras_list)

            add_ws_row = Adw.EntryRow(title="Add Extra Workspace")
            # Safely set placeholder text for compatibility
            if hasattr(add_ws_row, "set_placeholder_text"):
                add_ws_row.set_placeholder_text("e.g. name or ID > 10")
            else:
                try:
                    add_ws_row.set_property("placeholder-text", "e.g. name or ID > 10")
                except Exception:
                    pass
            add_ws_row.connect("apply", self._on_ws_added)
            ws_group.add(add_ws_row)

            self._editor_box.append(ws_group)

            # ── Action bar ────────────────────────────────────────────────────
            action_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            action_box.set_margin_top(8)

            apply_btn = Gtk.Button(label="Apply")
            apply_btn.add_css_class("suggested-action")
            apply_btn.connect("clicked", self._on_apply_clicked)
            apply_btn.set_hexpand(True)

            reload_btn = Gtk.Button(icon_name="system-reboot-symbolic")
            reload_btn.add_css_class("flat")
            reload_btn.set_tooltip_text("Reload Hyprland")
            reload_btn.connect("clicked", self._on_reload_clicked)

            action_box.append(apply_btn)
            action_box.append(reload_btn)
            self._editor_box.append(action_box)

            self._stack.set_visible_child_name("editor")

        except Exception as e:
            log.exception("Error in _build_editor: %s", e)
            from lib import utility
            utility.toast(self._toast_ov, f"Error building editor: {e}")

    def _make_ws_row(self, ws: str) -> Adw.ActionRow:
        row = Adw.ActionRow(title=ws)
        del_btn = Gtk.Button(icon_name="list-remove-symbolic")
        del_btn.add_css_class("flat")
        del_btn.set_valign(Gtk.Align.CENTER)
        del_btn.connect("clicked", lambda _: self._on_ws_removed(row, ws))
        row.add_suffix(del_btn)
        return row

    def _on_ws_toggled(self, btn: Gtk.CheckButton, ws: str) -> None:
        if self._selected is None:
            return
        
        active = btn.get_active()
        if active and ws not in self._selected.assigned_workspaces:
            self._selected.assigned_workspaces.append(ws)
        elif not active and ws in self._selected.assigned_workspaces:
            self._selected.assigned_workspaces.remove(ws)
            
        self._sync_workspaces_live()

    def _on_ws_added(self, entry: Adw.EntryRow) -> None:
        ws = entry.get_text().strip()
        if not ws or self._selected is None:
            return
        if ws in self._selected.assigned_workspaces:
            entry.set_text("")
            return

        self._selected.assigned_workspaces.append(ws)
        
        # If it's 1-10, just toggle the checkbox, otherwise add to extras list
        if ws.isdigit() and 1 <= int(ws) <= 10:
            if ws in self._ws_checks:
                self._ws_checks[ws].set_active(True)
        else:
            self._ws_extras_list.append(self._make_ws_row(ws))
            
        self._sync_workspaces_live()
        entry.set_text("")

    def _on_ws_removed(self, row: Adw.ActionRow, ws: str) -> None:
        if self._selected is None:
            return
        if ws in self._selected.assigned_workspaces:
            self._selected.assigned_workspaces.remove(ws)
            
        # If it's 1-10, update the checkbox (though extras list shouldn't have them)
        if ws.isdigit() and 1 <= int(ws) <= 10:
            if ws in self._ws_checks:
                self._ws_checks[ws].set_active(False)
        else:
            self._ws_extras_list.remove(row)
            
        self._sync_workspaces_live()

    def _sync_workspaces_live(self) -> None:
        """Apply current workspace assignments live and update the config."""
        if self._selected is None:
            return
        
        mon = self._selected
        name = mon.name
        workspaces = list(mon.assigned_workspaces)

        # Update preview
        if self._layout_preview:
            self._layout_preview.update_workspaces(name, workspaces)

        def _do_sync():
            # 1. Live apply via hyprctl
            # We need to apply ALL workspaces for this monitor.
            # Hyprland will move them to the specified monitor.
            for ws in workspaces:
                subprocess.run(["hyprctl", "keyword", "workspace", f"{ws},monitor:{name}"], capture_output=True)

            # 2. Update the config file
            # We need the full monitor line to call _write_monitor_line correctly.
            # We can build it from current UI state or just use the last known one.
            # Building it ensures we don't write stale data.
            line = _build_monitor_line(
                name=mon.name,
                mode=self._get_selected_mode() or mon.current_mode_str,
                pos_x=int(self._pos_x_row.get_value()),
                pos_y=int(self._pos_y_row.get_value()),
                scale=self._scale_row.get_value(),
                transform=self._get_selected_transform(),
                enabled=self._enabled_row.get_active(),
                mirror_of=self._get_selected_mirror(),
            )
            
            try:
                _write_monitor_line(name, line, workspaces)
                # Force a reload so the config changes take effect immediately
                subprocess.run(["hyprctl", "reload"], capture_output=True)
            except Exception as exc:
                log.error("Failed to sync workspaces to config: %s", exc)

        threading.Thread(target=_do_sync, daemon=True).start()

    # ── Helpers ───────────────────────────────────────────────────────────────

    @staticmethod
    def _modes_match(a: str, b: str) -> bool:
        """Compare modes tolerantly — both 155.00Hz and 155 match."""
        def normalise(s: str) -> str:
            s = re.sub(r"Hz$", "", s, flags=re.IGNORECASE).strip()
            # round refresh rate to 2dp for comparison
            m = re.match(r"^(\d+x\d+)@([\d.]+)$", s)
            if m:
                try:
                    return f"{m.group(1)}@{float(m.group(2)):.2f}"
                except ValueError:
                    pass
            return s
        return normalise(a) == normalise(b)

    def _get_selected_mode(self) -> str:
        """Return the raw mode string from the dropdown."""
        if self._custom_mode_row is not None:
            manual = self._custom_mode_row.get_text().strip()
            if manual:
                return _normalise_mode_label(manual)

        idx = int(self._mode_dropdown.get_selected())
        if 0 <= idx < len(self._mode_labels):
            return self._mode_labels[idx]
        return ""

    def _get_selected_transform(self) -> int:
        idx = self._transform_row.get_selected()
        if 0 <= idx < len(TRANSFORM_LABELS):
            return TRANSFORM_LABELS[idx][0]
        return 0

    def _get_selected_mirror(self) -> str:
        idx = self._mirror_row.get_selected()
        model = self._mirror_row.get_model()
        if model and idx < model.get_n_items():
            item = model.get_item(idx)
            name = item.get_string() if item else ""
            return "" if name == "(none)" else name
        return ""

    # ── Data loading ──────────────────────────────────────────────────────────

    def refresh(self) -> None:
        threading.Thread(target=self._do_refresh, daemon=True).start()

    def _do_refresh(self) -> None:
        monitors = _fetch_monitors()
        GLib.idle_add(self._apply_refresh, monitors)

    def _apply_refresh(self, monitors: list[MonitorInfo]) -> bool:
        prev_name = self._selected.name if self._selected else None
        self._monitors = monitors
        self._rebuild_list()

        # Re-select previously selected monitor and update self._selected reference
        if prev_name:
            for i, mon in enumerate(self._monitors):
                if mon.name == prev_name:
                    self._selected = mon  # Update reference to new data
                    row = self._list.get_row_at_index(i)
                    if row:
                        self._list.select_row(row)
                    break

        total = len(monitors)
        active = sum(1 for m in monitors if not m.disabled)
        self._count_lbl.set_text(f"{active}/{total} active")
        return GLib.SOURCE_REMOVE

    def _rebuild_list(self) -> None:
        while row := self._list.get_row_at_index(0):
            self._list.remove(row)
        for mon in self._monitors:
            self._list.append(self._make_list_row(mon))

    def _make_list_row(self, mon: MonitorInfo) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row._monitor = mon  # type: ignore[attr-defined]

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_start(12)
        box.set_margin_end(8)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)

        name_lbl = Gtk.Label(label=mon.name)
        name_lbl.set_xalign(0)
        name_lbl.set_hexpand(True)
        if mon.focused:
            name_lbl.add_css_class("accent")

        badge_text = "disabled" if mon.disabled else "active"
        badge = Gtk.Label(label=badge_text)
        badge.add_css_class("caption")
        badge.add_css_class("manager-badge")
        badge.add_css_class("keybind-badge-owned" if not mon.disabled else "keybind-badge-locked")

        top.append(name_lbl)
        top.append(badge)

        sub_lbl = Gtk.Label(label=mon.current_mode_str if not mon.disabled else mon.display_name)
        sub_lbl.set_xalign(0)
        sub_lbl.add_css_class("caption")
        sub_lbl.add_css_class("dim-label")
        sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)

        box.append(top)
        box.append(sub_lbl)
        row.set_child(box)
        return row

    # ── Events ────────────────────────────────────────────────────────────────

    def _on_add_headless_clicked(self, _btn: Gtk.Button) -> None:
        def _do_create():
            try:
                subprocess.run(["hyprctl", "output", "create", "headless"], check=True)
                GLib.idle_add(self.refresh)
            except Exception as e:
                from lib import utility
                utility.toast(self._toast_ov, f"Failed to create headless display: {e}")

        threading.Thread(target=_do_create, daemon=True).start()

    def _on_remove_headless_clicked(self, _btn: Gtk.Button, name: str) -> None:
        def _do_remove():
            try:
                subprocess.run(["hyprctl", "output", "remove", name], check=True)
                GLib.idle_add(self.refresh)
            except Exception as e:
                from lib import utility
                utility.toast(self._toast_ov, f"Failed to remove headless display: {e}")

        threading.Thread(target=_do_remove, daemon=True).start()

    def _on_row_selected(self, _lb: Gtk.ListBox, row: Optional[Gtk.ListBoxRow]) -> None:
        if row is None:
            self._selected = None
            self._stack.set_visible_child_name("placeholder")
            return
        mon = getattr(row, "_monitor", None)
        if mon is None:
            return
        self._selected = mon
        self._build_editor(mon)

    def _on_enabled_changed(self, *_) -> None:
        """Grey out editor controls when monitor is disabled."""
        enabled = self._enabled_row.get_active()
        for widget in (
            self._mode_dropdown, self._scale_row, self._transform_row,
            self._pos_x_row, self._pos_y_row, self._mirror_row,
        ):
            widget.set_sensitive(enabled)
        if self._custom_mode_row is not None:
            self._custom_mode_row.set_sensitive(enabled)

    def _on_position_spin_changed(self, *_args) -> None:
        if self._updating_position_widgets:
            return
        if self._selected is None or self._layout_preview is None:
            return

        x = int(self._pos_x_row.get_value())
        y = int(self._pos_y_row.get_value())
        self._layout_preview.update_monitor_position(self._selected.name, x, y)

    def _on_preview_selected(self, monitor_name: str) -> None:
        for i, mon in enumerate(self._monitors):
            if mon.name != monitor_name:
                continue
            row = self._list.get_row_at_index(i)
            if row:
                self._list.select_row(row)
            break

    def _on_preview_moved(self, monitor_name: str, x: int, y: int) -> None:
        if self._selected is None:
            return
        if monitor_name != self._selected.name:
            return

        self._updating_position_widgets = True
        self._pos_x_row.set_value(float(x))
        self._pos_y_row.set_value(float(y))
        self._updating_position_widgets = False

    def _on_apply_clicked(self, _btn: Gtk.Button) -> None:
        mon = self._selected
        if mon is None:
            return

        enabled   = self._enabled_row.get_active()
        mode      = self._get_selected_mode() or mon.current_mode_str
        scale     = self._scale_row.get_value()
        transform = self._get_selected_transform()
        pos_x     = int(self._pos_x_row.get_value())
        pos_y     = int(self._pos_y_row.get_value())
        mirror    = self._get_selected_mirror()
        workspaces = list(mon.assigned_workspaces)

        line = _build_monitor_line(
            name=mon.name, mode=mode,
            pos_x=pos_x, pos_y=pos_y,
            scale=scale, transform=transform,
            enabled=enabled, mirror_of=mirror,
        )

        threading.Thread(
            target=self._do_apply,
            args=(mon.name, line, workspaces),
            daemon=True,
        ).start()

    def _do_apply(self, name: str, line: str, workspaces: list[str]) -> None:
        from lib import utility
        ok, message = _apply_monitor_line(line)
        if not ok:
            utility.toast(self._toast_ov, f"Failed to apply monitor rule: {message}")
            return

        # Apply workspace rules live
        for ws in workspaces:
            subprocess.run(["hyprctl", "keyword", "workspace", f"{ws},monitor:{name}"], capture_output=True)

        try:
            _write_monitor_line(name, line, workspaces)
        except Exception as exc:
            utility.toast(self._toast_ov, f"Failed to save: {exc}")
            return

        utility.toast(self._toast_ov, f"{name} updated live and saved")
        GLib.idle_add(self._after_apply)

    def _after_apply(self) -> bool:
        self.refresh()
        return GLib.SOURCE_REMOVE

    def _on_reload_clicked(self, _btn: Gtk.Button) -> None:
        from lib import utility
        threading.Thread(
            target=lambda: subprocess.run(["hyprctl", "reload"], capture_output=True),
            daemon=True,
        ).start()
        utility.toast(self._toast_ov, "Hyprland reloading…")
