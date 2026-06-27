"""Cloud Center — Battery management page."""
from __future__ import annotations

import logging
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk

import lib.utility as utility

log = logging.getLogger(__name__)

BAT_PATH = Path("/sys/class/power_supply/BAT0")
THRESHOLD_PATH = BAT_PATH / "charge_control_end_threshold"
ASUS_MODE_PATH = Path("/sys/devices/platform/asus-nb-wmi/charge_mode")

_ASUS_MODES = ["Balanced", "Full Capacity", "Battery Care"]
_ASUS_MODE_DESCS = [
    "Charges to ~80%, suitable for daily use",
    "Charges to 100% for extended sessions",
    "Charges to ~60% for long-term battery health",
]


def _sysfs_int(rel: str, default: int = 0) -> int:
    try:
        return int((BAT_PATH / rel).read_text().strip())
    except Exception:
        return default


def _sysfs_str(rel: str, default: str = "N/A") -> str:
    try:
        v = (BAT_PATH / rel).read_text().strip()
        return v if v else default
    except Exception:
        return default


@dataclass
class BatteryInfo:
    percentage: int = 0
    status: str = "Unknown"
    voltage_uv: int = 0
    current_ua: int = 0
    charge_full_uah: int = 0
    charge_full_design_uah: int = 0
    cycle_count: int = 0
    manufacturer: str = "N/A"
    model: str = "N/A"
    technology: str = "N/A"
    serial: str = "N/A"
    charge_end_threshold: int = 100
    # From upower
    energy_wh: float = 0.0
    energy_full_wh: float = 0.0
    energy_full_design_wh: float = 0.0
    energy_rate_w: float = 0.0
    time_remaining_str: str = ""
    # ASUS WMI
    charge_mode: Optional[int] = None

    @property
    def voltage_v(self) -> float:
        return self.voltage_uv / 1_000_000

    @property
    def power_w(self) -> float:
        if self.energy_rate_w > 0.0:
            return self.energy_rate_w
        if self.voltage_uv > 0 and self.current_ua != 0:
            return self.voltage_v * abs(self.current_ua / 1_000_000)
        return 0.0

    @property
    def health_pct(self) -> float:
        if self.charge_full_design_uah > 0:
            return (self.charge_full_uah / self.charge_full_design_uah) * 100
        return 0.0


def _parse_upower(info: BatteryInfo) -> None:
    """Fill energy/rate/time fields from upower (runs in worker thread)."""
    try:
        r1 = subprocess.run(["upower", "-e"], capture_output=True, text=True, timeout=5)
        if r1.returncode != 0:
            return
        bat = next((ln.strip() for ln in r1.stdout.splitlines() if "BAT" in ln), None)
        if not bat:
            return
        r2 = subprocess.run(["upower", "-i", bat], capture_output=True, text=True, timeout=5)
        if r2.returncode != 0:
            return
        for line in r2.stdout.splitlines():
            k, _, v = line.strip().partition(":")
            k = k.strip()
            v = v.strip()
            if k == "energy" and "Wh" in v:
                info.energy_wh = float(v.split()[0])
            elif k == "energy-full" and "Wh" in v:
                info.energy_full_wh = float(v.split()[0])
            elif k == "energy-full-design" and "Wh" in v:
                info.energy_full_design_wh = float(v.split()[0])
            elif k == "energy-rate" and "W" in v:
                info.energy_rate_w = float(v.split()[0])
            elif k == "time to full":
                info.time_remaining_str = f"{v} to full"
            elif k == "time to empty":
                info.time_remaining_str = f"{v} to empty"
    except Exception as exc:
        log.debug("upower parse error: %s", exc)


def _write_sysfs(path: Path, value: str) -> bool:
    """Write to a sysfs file; falls back to pkexec tee on PermissionError."""
    try:
        path.write_text(value)
        return True
    except PermissionError:
        pass
    try:
        r = subprocess.run(
            ["pkexec", "tee", str(path)],
            input=value,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return r.returncode == 0
    except Exception:
        return False


class BatteryPage(Gtk.Box):

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._toast_ov = toast_overlay
        self._sources: list[int] = []
        self._threshold_debounce: int = 0
        self._pending_threshold: int = 100
        self._suppress_mode_signal: bool = False

        self._has_threshold = THRESHOLD_PATH.exists()
        self._has_asus_mode = ASUS_MODE_PATH.exists()

        self._build_ui()
        self._refresh()

        sid = GLib.timeout_add_seconds(30, self._on_refresh_timer)
        self._sources.append(sid)

    def do_unroot(self) -> None:
        if self._threshold_debounce:
            GLib.source_remove(self._threshold_debounce)
            self._threshold_debounce = 0
        for sid in self._sources:
            GLib.source_remove(sid)
        self._sources.clear()
        super().do_unroot()

    # ── UI construction ───────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        pref = Adw.PreferencesPage()
        self.append(pref)

        # ── Status ───────────────────────────────────────────────────────────
        status_group = Adw.PreferencesGroup()
        status_group.set_title("Battery Status")
        pref.add(status_group)

        hero_row = Adw.ActionRow()
        hero_row.set_activatable(False)
        self._hero_row = hero_row

        self._bat_icon = Gtk.Image.new_from_icon_name("battery-good-symbolic")
        self._bat_icon.set_pixel_size(32)
        hero_row.add_prefix(self._bat_icon)

        self._pct_label = Gtk.Label(label="—%")
        self._pct_label.add_css_class("title-1")
        self._pct_label.set_valign(Gtk.Align.CENTER)
        hero_row.add_suffix(self._pct_label)
        status_group.add(hero_row)

        # Progress bar row
        level_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        level_box.set_margin_start(12)
        level_box.set_margin_end(12)
        level_box.set_margin_bottom(10)
        self._level_bar = Gtk.LevelBar()
        self._level_bar.set_mode(Gtk.LevelBarMode.CONTINUOUS)
        self._level_bar.set_min_value(0.0)
        self._level_bar.set_max_value(1.0)
        self._level_bar.set_value(0.0)
        # Only keep a low-battery indicator offset
        self._level_bar.remove_offset_value("high")
        self._level_bar.remove_offset_value("full")
        self._level_bar.add_offset_value("low", 0.20)
        level_box.append(self._level_bar)
        status_group.add(level_box)

        self._state_row = self._info_row("State", "—")
        self._power_row = self._info_row("Power Draw", "—")
        self._time_row = self._info_row("Time Remaining", "—")
        for row in (self._state_row, self._power_row, self._time_row):
            status_group.add(row)

        # ── Health ───────────────────────────────────────────────────────────
        health_group = Adw.PreferencesGroup()
        health_group.set_title("Battery Health")
        pref.add(health_group)

        self._health_row = self._info_row("Health", "—")
        self._capacity_row = self._info_row("Capacity", "—")
        self._voltage_row = self._info_row("Voltage", "—")
        self._cycles_row = self._info_row("Charge Cycles", "—")
        for row in (self._health_row, self._capacity_row, self._voltage_row, self._cycles_row):
            health_group.add(row)

        # ── Charge limit ─────────────────────────────────────────────────────
        if self._has_threshold:
            limit_group = Adw.PreferencesGroup()
            limit_group.set_title("Charge Limit")
            limit_group.set_description(
                "Stop charging before 100% to extend long-term battery lifespan."
            )
            pref.add(limit_group)

            limit_row = Adw.ActionRow()
            limit_row.set_title("Stop Charging At")
            limit_row.set_activatable(False)

            ctrl_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            ctrl_box.set_valign(Gtk.Align.CENTER)

            self._threshold_scale = Gtk.Scale.new_with_range(
                Gtk.Orientation.HORIZONTAL, 40, 100, 5
            )
            self._threshold_scale.set_size_request(180, -1)
            self._threshold_scale.set_draw_value(False)
            for mark in (60, 80, 100):
                self._threshold_scale.add_mark(mark, Gtk.PositionType.BOTTOM, f"{mark}%")
            self._threshold_scale.connect("value-changed", self._on_threshold_changed)
            ctrl_box.append(self._threshold_scale)

            self._threshold_label = Gtk.Label(label="100%")
            self._threshold_label.set_width_chars(5)
            self._threshold_label.set_xalign(1.0)
            ctrl_box.append(self._threshold_label)

            limit_row.add_suffix(ctrl_box)
            limit_group.add(limit_row)

        # ── ASUS charge mode ─────────────────────────────────────────────────
        if self._has_asus_mode:
            mode_group = Adw.PreferencesGroup()
            mode_group.set_title("Charge Mode")
            pref.add(mode_group)

            mode_strings = Gtk.StringList.new(_ASUS_MODES)
            self._mode_row = Adw.ComboRow()
            self._mode_row.set_title("Charging Mode")
            self._mode_row.set_model(mode_strings)
            self._mode_row.connect("notify::selected", self._on_mode_changed)
            mode_group.add(self._mode_row)

        # ── Device info ──────────────────────────────────────────────────────
        info_group = Adw.PreferencesGroup()
        info_group.set_title("Device Information")
        pref.add(info_group)

        self._mfr_row = self._info_row("Manufacturer", "—")
        self._model_row = self._info_row("Model", "—")
        self._tech_row = self._info_row("Technology", "—")
        self._serial_row = self._info_row("Serial Number", "—")
        for row in (self._mfr_row, self._model_row, self._tech_row, self._serial_row):
            info_group.add(row)

    @staticmethod
    def _info_row(title: str, value: str) -> Adw.ActionRow:
        row = Adw.ActionRow()
        row.set_title(title)
        row.set_activatable(False)
        lbl = Gtk.Label(label=value)
        lbl.set_valign(Gtk.Align.CENTER)
        lbl.add_css_class("dim-label")
        row.add_suffix(lbl)
        row._value_label = lbl  # type: ignore[attr-defined]
        return row

    # ── Data refresh ─────────────────────────────────────────────────────────

    def _on_refresh_timer(self) -> bool:
        self._refresh()
        return GLib.SOURCE_CONTINUE

    def _refresh(self) -> None:
        threading.Thread(target=self._do_refresh, daemon=True).start()

    def _do_refresh(self) -> None:
        info = BatteryInfo(
            percentage=_sysfs_int("capacity"),
            status=_sysfs_str("status"),
            voltage_uv=_sysfs_int("voltage_now"),
            current_ua=_sysfs_int("current_now"),
            charge_full_uah=_sysfs_int("charge_full"),
            charge_full_design_uah=_sysfs_int("charge_full_design"),
            cycle_count=_sysfs_int("cycle_count"),
            manufacturer=_sysfs_str("manufacturer"),
            model=_sysfs_str("model_name"),
            technology=_sysfs_str("technology"),
            serial=_sysfs_str("serial_number"),
            charge_end_threshold=_sysfs_int("charge_control_end_threshold", 100)
            if self._has_threshold
            else 100,
        )
        _parse_upower(info)
        if self._has_asus_mode:
            try:
                info.charge_mode = int(ASUS_MODE_PATH.read_text().strip())
            except Exception:
                info.charge_mode = None
        GLib.idle_add(self._apply_info, info)

    def _apply_info(self, info: BatteryInfo) -> bool:
        self._bat_icon.set_from_icon_name(self._status_icon_name(info))
        self._pct_label.set_label(f"{info.percentage}%")
        self._hero_row.set_title(f"Battery — {info.status}")
        if info.power_w > 0.01:
            self._hero_row.set_subtitle(f"{info.power_w:.1f} W")
        else:
            self._hero_row.set_subtitle("")
        self._level_bar.set_value(info.percentage / 100.0)

        self._state_row._value_label.set_label(info.status)  # type: ignore[attr-defined]
        self._power_row._value_label.set_label(  # type: ignore[attr-defined]
            f"{info.power_w:.2f} W" if info.power_w > 0.01 else "—"
        )
        self._time_row._value_label.set_label(  # type: ignore[attr-defined]
            info.time_remaining_str if info.time_remaining_str else "—"
        )

        self._health_row._value_label.set_label(  # type: ignore[attr-defined]
            f"{info.health_pct:.1f}%" if info.health_pct > 0 else "—"
        )
        cap_str = self._capacity_str(info)
        self._capacity_row._value_label.set_label(cap_str)  # type: ignore[attr-defined]
        self._voltage_row._value_label.set_label(  # type: ignore[attr-defined]
            f"{info.voltage_v:.3f} V" if info.voltage_v > 0 else "—"
        )
        cycles = info.cycle_count
        self._cycles_row._value_label.set_label(  # type: ignore[attr-defined]
            str(cycles) if cycles > 0 else "N/A"
        )

        if self._has_threshold and self._threshold_debounce == 0:
            self._threshold_scale.set_value(info.charge_end_threshold)
            self._threshold_label.set_label(f"{info.charge_end_threshold}%")

        if self._has_asus_mode and info.charge_mode is not None:
            if 0 <= info.charge_mode < len(_ASUS_MODES):
                self._suppress_mode_signal = True
                self._mode_row.set_selected(info.charge_mode)
                self._suppress_mode_signal = False

        self._mfr_row._value_label.set_label(info.manufacturer)  # type: ignore[attr-defined]
        self._model_row._value_label.set_label(info.model)  # type: ignore[attr-defined]
        self._tech_row._value_label.set_label(info.technology)  # type: ignore[attr-defined]
        self._serial_row._value_label.set_label(info.serial)  # type: ignore[attr-defined]

        return GLib.SOURCE_REMOVE

    @staticmethod
    def _status_icon_name(info: BatteryInfo) -> str:
        pct = info.percentage
        charging = info.status.lower() == "charging"
        suffix = "-charging-symbolic" if charging else "-symbolic"
        if pct >= 90:
            stem = "battery-full"
        elif pct >= 60:
            stem = "battery-good"
        elif pct >= 30:
            stem = "battery-medium"
        elif pct >= 10:
            stem = "battery-low"
        else:
            stem = "battery-caution"
        return stem + suffix

    @staticmethod
    def _capacity_str(info: BatteryInfo) -> str:
        if info.energy_full_wh > 0:
            return f"{info.energy_wh:.1f} / {info.energy_full_wh:.1f} Wh"
        if info.charge_full_uah > 0 and info.voltage_v > 0:
            full = (info.charge_full_uah / 1e6) * info.voltage_v
            design = (info.charge_full_design_uah / 1e6) * info.voltage_v
            return f"{full:.1f} / {design:.1f} Wh (est.)"
        return "—"

    # ── Charge limit control ──────────────────────────────────────────────────

    def _on_threshold_changed(self, scale: Gtk.Scale) -> None:
        value = int(scale.get_value())
        self._threshold_label.set_label(f"{value}%")
        self._pending_threshold = value

        if self._threshold_debounce:
            GLib.source_remove(self._threshold_debounce)
            self._threshold_debounce = 0

        self._threshold_debounce = GLib.timeout_add(800, self._commit_threshold)

    def _commit_threshold(self) -> bool:
        value = self._pending_threshold
        self._threshold_debounce = 0
        threading.Thread(
            target=self._do_write_threshold, args=(value,), daemon=True
        ).start()
        return GLib.SOURCE_REMOVE

    def _do_write_threshold(self, value: int) -> None:
        ok = _write_sysfs(THRESHOLD_PATH, str(value))
        msg = (
            f"Charge limit set to {value}%"
            if ok
            else "Failed to set charge limit — permission denied"
        )
        utility.toast(self._toast_ov, msg)

    # ── ASUS charge mode control ──────────────────────────────────────────────

    def _on_mode_changed(self, row: Adw.ComboRow, _param: object) -> None:
        if self._suppress_mode_signal:
            return
        mode = row.get_selected()
        threading.Thread(
            target=self._do_write_mode, args=(mode,), daemon=True
        ).start()

    def _do_write_mode(self, mode: int) -> None:
        ok = _write_sysfs(ASUS_MODE_PATH, str(mode))
        label = _ASUS_MODES[mode] if 0 <= mode < len(_ASUS_MODES) else str(mode)
        msg = (
            f"Charge mode set to {label}"
            if ok
            else "Failed to set charge mode — permission denied"
        )
        utility.toast(self._toast_ov, msg)
