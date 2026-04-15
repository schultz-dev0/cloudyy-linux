"""Cloud Center — Monitor Editor page.

Two-panel layout mirroring the keybind/wifi pages:
  Left:  list of connected monitors (from hyprctl monitors -j)
  Right: per-monitor settings editor

Writes to ~/.config/hypr/user-configs/user_monitors.conf
and reloads Hyprland on apply.
"""
from __future__ import annotations

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

    @property
    def current_mode_str(self) -> str:
        """e.g. '2560x1440@155.00Hz'"""
        return f"{self.width}x{self.height}@{self.refresh_rate:.2f}Hz"

    @property
    def display_name(self) -> str:
        return self.model or self.description or self.name


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

    monitors = []
    for m in data:
        monitors.append(MonitorInfo(
            name          = m.get("name", ""),
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
            available_modes = m.get("availableModes", []),
        ))
    return monitors


# ── Config I/O ────────────────────────────────────────────────────────────────

def _parse_conf() -> dict[str, str]:
    """Return {monitor_name: raw_line} from user_monitors.conf."""
    result: dict[str, str] = {}
    if not MONITORS_CONF.exists():
        return result
    try:
        for line in MONITORS_CONF.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if stripped.startswith("monitor="):
                # monitor=NAME,...
                rest = stripped[len("monitor="):]
                name = rest.split(",")[0].strip()
                if name:
                    result[name] = stripped
    except OSError:
        pass
    return result


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


def _write_monitor_line(name: str, line: str) -> None:
    """Insert or replace the monitor= line for `name` in user_monitors.conf."""
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
    replaced = False
    for raw in existing:
        stripped = raw.strip()
        if stripped.startswith("monitor="):
            rest = stripped[len("monitor="):]
            existing_name = rest.split(",")[0].strip()
            if existing_name == name:
                out_lines.append(line + "\n")
                replaced = True
                continue
        out_lines.append(raw if raw.endswith("\n") else raw + "\n")

    if not replaced:
        if not out_lines:
            out_lines = [l for l in header.splitlines(keepends=True)]
        out_lines.append(line + "\n")

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

    log.info("Wrote monitor config for %s: %s", name, line)


# ── GTK Page ──────────────────────────────────────────────────────────────────

class MonitorEditorPage(Gtk.Box):
    """Two-panel monitor editor."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.HORIZONTAL)
        self._toast_ov  = toast_overlay
        self._monitors: list[MonitorInfo] = []
        self._selected: Optional[MonitorInfo] = None

        self._build_ui()
        self.refresh()

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

        hdr.append(title)
        hdr.append(self._count_lbl)
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
        self._editor_box.append(info_box)

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

        self._mode_row = Adw.ComboRow(title="Resolution & Refresh Rate")
        mode_labels = mon.available_modes if mon.available_modes else [mon.current_mode_str]
        self._mode_row.set_model(Gtk.StringList.new(mode_labels))

        # Pre-select the current mode
        current = mon.current_mode_str
        for i, m in enumerate(mode_labels):
            if self._modes_match(m, current):
                self._mode_row.set_selected(i)
                break

        mode_group.add(self._mode_row)

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
        self._transform_row.set_model(
            Gtk.StringList.new([label for _, label in TRANSFORM_LABELS])
        )
        self._transform_row.set_selected(
            next((i for i, (v, _) in enumerate(TRANSFORM_LABELS) if v == mon.transform), 0)
        )
        mode_group.add(self._transform_row)
        self._editor_box.append(mode_group)

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
        pos_group.add(self._pos_y_row)
        self._editor_box.append(pos_group)

        # ── Mirror ────────────────────────────────────────────────────────
        mirror_group = Adw.PreferencesGroup(title="Mirror")
        other_names = ["(none)"] + [m.name for m in self._monitors if m.name != mon.name]
        self._mirror_row = Adw.ComboRow(title="Mirror of")
        self._mirror_row.set_model(Gtk.StringList.new(other_names))

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
        """Return the raw mode string from the combo row."""
        idx = self._mode_row.get_selected()
        model = self._mode_row.get_model()
        if model and idx < model.get_n_items():
            item = model.get_item(idx)
            return item.get_string() if item else ""
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

        # Re-select previously selected monitor
        if prev_name:
            for i, mon in enumerate(self._monitors):
                if mon.name == prev_name:
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
            self._mode_row, self._scale_row, self._transform_row,
            self._pos_x_row, self._pos_y_row, self._mirror_row,
        ):
            widget.set_sensitive(enabled)

    def _on_apply_clicked(self, _btn: Gtk.Button) -> None:
        mon = self._selected
        if mon is None:
            return

        enabled   = self._enabled_row.get_active()
        mode      = self._get_selected_mode()
        scale     = self._scale_row.get_value()
        transform = self._get_selected_transform()
        pos_x     = int(self._pos_x_row.get_value())
        pos_y     = int(self._pos_y_row.get_value())
        mirror    = self._get_selected_mirror()

        line = _build_monitor_line(
            name=mon.name, mode=mode,
            pos_x=pos_x, pos_y=pos_y,
            scale=scale, transform=transform,
            enabled=enabled, mirror_of=mirror,
        )

        threading.Thread(
            target=self._do_apply,
            args=(mon.name, line),
            daemon=True,
        ).start()

    def _do_apply(self, name: str, line: str) -> None:
        from lib import utility
        try:
            _write_monitor_line(name, line)
        except Exception as exc:
            utility.toast(self._toast_ov, f"Failed to save: {exc}")
            return

        subprocess.run(["hyprctl", "reload"], capture_output=True)
        utility.toast(self._toast_ov, f"{name} updated — Hyprland reloaded")
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
