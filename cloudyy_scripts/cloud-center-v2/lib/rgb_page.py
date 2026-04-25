"""Cloud Center — OpenRGB manager page."""
from __future__ import annotations

import logging
import re
import socket
import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from gi.repository import Adw, Gdk, GLib, Gtk

log = logging.getLogger(__name__)

_OPENRGB_HOST = "127.0.0.1"
_OPENRGB_PORT = 6742
_PROFILE_DIR  = Path.home() / ".config" / "OpenRGB"

_COMMON_MODES = ["static", "breathing", "rainbow", "flashing", "off"]


# ── Data model ────────────────────────────────────────────────────────────────

@dataclass
class RGBDevice:
    index: int
    name: str
    modes: list[str] = field(default_factory=list)


# ── openrgb helpers ──────────────────────────────────────────────────────────

def _server_reachable(timeout: float = 1.5) -> bool:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        result = s.connect_ex((_OPENRGB_HOST, _OPENRGB_PORT))
        s.close()
        return result == 0
    except Exception:
        return False


def _run_rgb(args: list[str], timeout: int = 8) -> tuple[bool, str]:
    try:
        r = subprocess.run(
            ["openrgb", "--client", f"{_OPENRGB_HOST}:{_OPENRGB_PORT}"] + args,
            capture_output=True, text=True, timeout=timeout,
        )
        return r.returncode == 0, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except FileNotFoundError:
        return False, "openrgb not found"


def _start_service() -> bool:
    try:
        r = subprocess.run(
            ["systemctl", "--user", "restart", "openrgb.service"],
            capture_output=True, timeout=10,
        )
        return r.returncode == 0
    except Exception:
        return False


def _get_devices() -> list[RGBDevice]:
    ok, out = _run_rgb(["--list-devices"])
    if not ok or not out.strip():
        return []
    return _parse_devices(out)


def _parse_devices(text: str) -> list[RGBDevice]:
    devices: list[RGBDevice] = []
    current: Optional[RGBDevice] = None
    controller_count: Optional[int] = None

    for line in text.splitlines():
        # openrgb --client reports controller count; use it to drop duplicates
        m = re.search(r"controller count from server:\s*(\d+)", line)
        if m:
            controller_count = int(m.group(1))
            continue

        # "0: Device Name" — actual openrgb --list-devices format
        m = re.match(r"^(\d+):\s+(.+)", line)
        if m:
            idx = int(m.group(1))
            # Stop if we've already collected all real controllers
            if controller_count is not None and idx >= controller_count:
                if current is not None:
                    devices.append(current)
                    current = None
                break
            if current is not None:
                devices.append(current)
            current = RGBDevice(index=idx, name=m.group(2).strip())
            continue

        # "  Modes: Static Breathing ..." line
        if current is not None:
            m = re.match(r"^\s+Modes:\s+(.+)", line)
            if m:
                raw = m.group(1)
                # Tokens are space-separated; multi-word modes are single-quoted
                tokens = re.findall(r"'[^']*'|\S+", raw)
                for tok in tokens:
                    mode = tok.strip("'[]").lower()
                    if mode and mode not in current.modes:
                        current.modes.append(mode)

    if current is not None:
        devices.append(current)

    # Fall back to common modes if device has none listed
    for d in devices:
        if not d.modes:
            d.modes = list(_COMMON_MODES)

    return devices


def _get_profiles() -> list[str]:
    try:
        return sorted(
            p.stem for p in _PROFILE_DIR.glob("*.orp")
        )
    except Exception:
        return []


def _load_profile(name: str) -> tuple[bool, str]:
    return _run_rgb(["--profile", name])


def _save_profile(name: str) -> tuple[bool, str]:
    return _run_rgb(["--save-profile", name])


def _set_color(device_idx: int, hex_color: str) -> None:
    _run_rgb(["--device", str(device_idx), "--mode", "static",
              "--color", hex_color])


def _set_mode(device_idx: int, mode: str) -> None:
    _run_rgb(["--device", str(device_idx), "--mode", mode])


def _set_brightness(device_idx: int, value: int) -> None:
    _run_rgb(["--device", str(device_idx), "--brightness", str(value)])


# ── Page ──────────────────────────────────────────────────────────────────────

class RGBPage(Gtk.Box):
    """OpenRGB device control page."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._toast_ov = toast_overlay
        self._devices: list[RGBDevice] = []
        self._profiles: list[str] = []
        self._server_ok = False
        self._device_widgets: list[Gtk.Widget] = []
        self._debounce_ids: dict[int, int] = {}  # device_idx → GLib source id

        self._build_ui()
        self._auto_start_and_refresh()

    # ── UI construction ───────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        # ── Toolbar ──
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        toolbar.set_margin_start(16)
        toolbar.set_margin_end(12)
        toolbar.set_margin_top(10)
        toolbar.set_margin_bottom(6)

        title = Gtk.Label(label="RGB Lighting")
        title.add_css_class("heading")
        title.set_xalign(0)
        title.set_hexpand(True)

        self._status_label = Gtk.Label(label="")
        self._status_label.add_css_class("dim-label")
        self._status_label.add_css_class("caption")

        self._spinner = Gtk.Spinner()
        self._spinner.set_visible(False)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Refresh devices")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        toolbar.append(title)
        toolbar.append(self._status_label)
        toolbar.append(self._spinner)
        toolbar.append(refresh_btn)
        self.append(toolbar)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # ── Server unavailable banner ──
        self._banner = Adw.Banner()
        self._banner.set_title("OpenRGB server is not running")
        self._banner.set_button_label("Restart Server")
        self._banner.connect("button-clicked", self._on_restart_server)
        self._banner.set_revealed(False)
        self.append(self._banner)

        # ── Scrollable content ──
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_vexpand(True)

        self._content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self._content.set_margin_start(16)
        self._content.set_margin_end(16)
        self._content.set_margin_top(12)
        self._content.set_margin_bottom(16)

        clamp = Adw.Clamp()
        clamp.set_child(self._content)
        scroll.set_child(clamp)
        self.append(scroll)

    # ── Content population ────────────────────────────────────────────────────

    def _clear_content(self) -> None:
        child = self._content.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._content.remove(child)
            child = nxt
        self._device_widgets.clear()

    def _build_content(self) -> None:
        self._clear_content()

        if not self._server_ok:
            placeholder = Adw.StatusPage(
                icon_name="applications-games-symbolic",
                title="Server Unavailable",
                description="The OpenRGB server could not be reached.\nClick 'Restart Server' in the banner above.",
            )
            placeholder.set_vexpand(True)
            self._content.append(placeholder)
            return

        if not self._devices:
            placeholder = Adw.StatusPage(
                icon_name="applications-games-symbolic",
                title="No RGB Devices Found",
                description="No compatible devices were detected.",
            )
            placeholder.set_vexpand(True)
            self._content.append(placeholder)
            return

        # ── Profile section ──
        profile_group = self._build_profile_group()
        self._content.append(profile_group)

        spacer = Gtk.Box()
        spacer.set_size_request(-1, 12)
        self._content.append(spacer)

        # ── Device sections ──
        for device in self._devices:
            group = self._build_device_group(device)
            self._content.append(group)
            spacer = Gtk.Box()
            spacer.set_size_request(-1, 12)
            self._content.append(spacer)

    def _build_profile_group(self) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title("Profiles")

        # Profile list row
        self._profile_combo = Adw.ComboRow()
        self._profile_combo.set_title("Load Profile")
        self._profile_combo.set_subtitle("Apply a saved color profile to all devices")
        self._profile_combo.set_icon_name("document-open-symbolic")
        self._refresh_profile_combo()
        self._profile_combo.connect("notify::selected", self._on_profile_selected)
        group.add(self._profile_combo)

        # Save profile row
        save_row = Adw.EntryRow()
        save_row.set_title("Save as New Profile")
        save_row.set_input_purpose(Gtk.InputPurpose.FREE_FORM)
        save_row.connect("apply", self._on_save_profile)

        save_btn = Gtk.Button(label="Save")
        save_btn.add_css_class("suggested-action")
        save_btn.set_valign(Gtk.Align.CENTER)
        save_btn.connect("clicked", lambda _, r=save_row: self._on_save_profile(r))
        save_row.add_suffix(save_btn)
        group.add(save_row)

        return group

    def _refresh_profile_combo(self) -> None:
        strings = Gtk.StringList.new(self._profiles if self._profiles else ["(no profiles)"])
        self._profile_combo.set_model(strings)
        self._profile_combo.set_sensitive(bool(self._profiles))

    def _build_device_group(self, device: RGBDevice) -> Adw.PreferencesGroup:
        group = Adw.PreferencesGroup()
        group.set_title(device.name)

        # ── Color picker row ──
        color_row = Adw.ActionRow()
        color_row.set_title("Color")
        color_row.set_subtitle("Apply a static color to all LEDs")
        color_row.set_icon_name("color-picker-symbolic")

        color_btn = Gtk.ColorButton()
        color_btn.set_valign(Gtk.Align.CENTER)
        color_btn.set_use_alpha(False)
        color_btn.connect("color-set", self._on_color_set, device.index)
        color_row.add_suffix(color_btn)
        color_row.set_activatable_widget(color_btn)
        group.add(color_row)

        # ── Mode selector row ──
        mode_row = Adw.ComboRow()
        mode_row.set_title("Effect Mode")
        mode_row.set_icon_name("media-playback-start-symbolic")
        display_modes = [m.capitalize() for m in device.modes]
        mode_row.set_model(Gtk.StringList.new(display_modes))
        mode_row.connect("notify::selected", self._on_mode_changed, device)
        group.add(mode_row)

        # ── Brightness slider row ──
        brightness_row = Adw.ActionRow()
        brightness_row.set_title("Brightness")
        brightness_row.set_icon_name("display-brightness-symbolic")

        adj = Gtk.Adjustment(value=100, lower=0, upper=100, step_increment=1, page_increment=10)
        scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
        scale.set_size_request(160, -1)
        scale.set_digits(0)
        scale.set_draw_value(True)
        scale.set_value_pos(Gtk.PositionType.RIGHT)
        scale.set_hexpand(True)
        scale.set_valign(Gtk.Align.CENTER)
        scale.connect("value-changed", self._on_brightness_changed, device.index)
        brightness_row.add_suffix(scale)
        group.add(brightness_row)

        return group

    # ── Server management ─────────────────────────────────────────────────────

    def _auto_start_and_refresh(self) -> None:
        self._spinner.set_visible(True)
        self._spinner.start()
        self._status_label.set_text("Connecting…")
        threading.Thread(target=self._do_auto_start, daemon=True).start()

    def _do_auto_start(self) -> None:
        if _server_reachable():
            GLib.idle_add(self._do_refresh_ui)
            return
        # Server not reachable — try restarting the service
        _start_service()
        # Wait up to 8 seconds for the server to come up
        for _ in range(8):
            import time; time.sleep(1)
            if _server_reachable():
                break
        GLib.idle_add(self._do_refresh_ui)

    def _on_restart_server(self, _banner: Adw.Banner) -> None:
        self._spinner.set_visible(True)
        self._spinner.start()
        self._status_label.set_text("Restarting server…")
        threading.Thread(target=self._do_restart_server, daemon=True).start()

    def _do_restart_server(self) -> None:
        _start_service()
        import time
        for _ in range(8):
            time.sleep(1)
            if _server_reachable():
                break
        GLib.idle_add(self._do_refresh_ui)

    # ── Refresh ───────────────────────────────────────────────────────────────

    def refresh(self) -> None:
        self._spinner.set_visible(True)
        self._spinner.start()
        self._status_label.set_text("Refreshing…")
        threading.Thread(target=self._do_refresh_ui, daemon=True).start()

    def _do_refresh_ui(self) -> None:
        """Run in background thread — fetch state, then update UI."""
        server_ok = _server_reachable()
        devices   = _get_devices() if server_ok else []
        profiles  = _get_profiles()
        GLib.idle_add(self._apply_refresh, server_ok, devices, profiles)

    def _apply_refresh(self, server_ok: bool, devices: list[RGBDevice],
                       profiles: list[str]) -> bool:
        self._server_ok = server_ok
        self._devices   = devices
        self._profiles  = profiles

        self._spinner.stop()
        self._spinner.set_visible(False)
        self._banner.set_revealed(not server_ok)

        if server_ok:
            self._status_label.set_text(
                f"{len(devices)} device{'s' if len(devices) != 1 else ''}"
            )
        else:
            self._status_label.set_text("Server unavailable")

        self._build_content()
        return GLib.SOURCE_REMOVE

    # ── Callbacks ─────────────────────────────────────────────────────────────

    def _on_color_set(self, btn: Gtk.ColorButton, device_idx: int) -> None:
        rgba = btn.get_rgba()
        hex_color = "%02X%02X%02X" % (
            int(rgba.red * 255),
            int(rgba.green * 255),
            int(rgba.blue * 255),
        )
        threading.Thread(
            target=_set_color, args=(device_idx, hex_color), daemon=True
        ).start()

    def _on_mode_changed(self, combo: Adw.ComboRow, _param,
                         device: RGBDevice) -> None:
        idx = combo.get_selected()
        if idx < len(device.modes):
            mode = device.modes[idx]
            threading.Thread(
                target=_set_mode, args=(device.index, mode), daemon=True
            ).start()

    def _on_brightness_changed(self, scale: Gtk.Scale, device_idx: int) -> None:
        # Debounce: cancel pending call for this device
        if device_idx in self._debounce_ids:
            GLib.source_remove(self._debounce_ids[device_idx])

        value = int(scale.get_value())

        def _send():
            del self._debounce_ids[device_idx]
            threading.Thread(
                target=_set_brightness, args=(device_idx, value), daemon=True
            ).start()
            return GLib.SOURCE_REMOVE

        self._debounce_ids[device_idx] = GLib.timeout_add(200, _send)

    def _on_profile_selected(self, combo: Adw.ComboRow, _param) -> None:
        if not self._profiles:
            return
        idx = combo.get_selected()
        if idx < len(self._profiles):
            name = self._profiles[idx]
            threading.Thread(target=self._do_load_profile, args=(name,), daemon=True).start()

    def _do_load_profile(self, name: str) -> None:
        ok, out = _load_profile(name)
        msg = f"Loaded profile: {name}" if ok else f"Failed to load profile: {out[:80]}"
        from lib import utility
        utility.toast(self._toast_ov, msg)

    def _on_save_profile(self, entry_row: Adw.EntryRow) -> None:
        name = entry_row.get_text().strip()
        if not name:
            return
        entry_row.set_text("")
        threading.Thread(target=self._do_save_profile, args=(name,), daemon=True).start()

    def _do_save_profile(self, name: str) -> None:
        ok, out = _save_profile(name)
        msg = f"Saved profile: {name}" if ok else f"Failed to save: {out[:80]}"
        from lib import utility
        utility.toast(self._toast_ov, msg)
        if ok:
            self._profiles = _get_profiles()
            GLib.idle_add(self._refresh_profile_combo)
