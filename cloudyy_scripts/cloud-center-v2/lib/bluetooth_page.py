"""Cloud Center — Bluetooth manager page using bluetoothctl."""
from __future__ import annotations

import concurrent.futures
import logging
import re
import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Optional

from gi.repository import Adw, GLib, Gtk, Pango

log = logging.getLogger(__name__)


# ── Data model ────────────────────────────────────────────────────────────────


@dataclass
class BluetoothDevice:
    address: str
    name: str
    paired: bool = False
    connected: bool = False
    trusted: bool = False
    device_type: str = ""

    @property
    def display_name(self) -> str:
        return self.name if self.name and self.name != self.address else self.address


# ── bluetoothctl helpers ──────────────────────────────────────────────────────


def _run_bt(args: list[str], timeout: int = 6) -> tuple[bool, str]:
    try:
        r = subprocess.run(
            ["bluetoothctl"] + args,
            capture_output=True, text=True, timeout=timeout,
        )
        return r.returncode == 0, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except FileNotFoundError:
        return False, "bluetoothctl not found"


_devices_cache: list[BluetoothDevice] = []
_devices_cache_time: float = 0.0
_DEVICES_CACHE_TTL: float = 5.0


def get_bt_powered() -> bool:
    _, out = _run_bt(["show"])
    return "Powered: yes" in out


def set_bt_power(on: bool) -> bool:
    ok, _ = _run_bt(["power", "on" if on else "off"])
    return ok


def get_devices(force: bool = False) -> list[BluetoothDevice]:
    global _devices_cache, _devices_cache_time
    if not force and time.monotonic() - _devices_cache_time < _DEVICES_CACHE_TTL:
        return list(_devices_cache)

    _, paired_out = _run_bt(["devices", "Paired"])
    paired_addrs: set[str] = set()
    for line in paired_out.splitlines():
        m = re.match(r"Device\s+([\w:]+)", line)
        if m:
            paired_addrs.add(m.group(1))

    _, devices_out = _run_bt(["devices"])
    addr_name_pairs: list[tuple[str, str]] = []
    for line in devices_out.splitlines():
        m = re.match(r"Device\s+([\w:]+)\s+(.*)", line)
        if m:
            addr_name_pairs.append((m.group(1), m.group(2).strip()))

    def _fetch_one(addr: str, name: str) -> BluetoothDevice:
        _, info = _run_bt(["info", addr])
        connected = "Connected: yes" in info
        paired = addr in paired_addrs or "Paired: yes" in info
        trusted = "Trusted: yes" in info
        dtype = ""
        for ln in info.splitlines():
            if "Icon:" in ln:
                dtype = ln.split(":", 1)[1].strip()
                break
        return BluetoothDevice(
            address=addr, name=name,
            paired=paired, connected=connected, trusted=trusted,
            device_type=dtype,
        )

    results: list[BluetoothDevice] = []
    if addr_name_pairs:
        max_workers = min(4, len(addr_name_pairs))
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as ex:
            futs = {ex.submit(_fetch_one, addr, name): None for addr, name in addr_name_pairs}
            for fut in concurrent.futures.as_completed(futs):
                try:
                    results.append(fut.result())
                except Exception:
                    pass

    results.sort(key=lambda d: (not d.connected, not d.paired, d.display_name.lower()))
    _devices_cache = results
    _devices_cache_time = time.monotonic()
    return results


def connect_device(address: str) -> tuple[bool, str]:
    return _run_bt(["connect", address], timeout=18)


def disconnect_device(address: str) -> tuple[bool, str]:
    return _run_bt(["disconnect", address], timeout=10)


def remove_device(address: str) -> tuple[bool, str]:
    return _run_bt(["remove", address], timeout=8)


def _icon_for_type(device_type: str) -> str:
    return {
        "audio-headset": "audio-headset-symbolic",
        "audio-headphones": "audio-headphones-symbolic",
        "phone": "phone-symbolic",
        "computer": "computer-symbolic",
        "input-keyboard": "input-keyboard-symbolic",
        "input-mouse": "input-mouse-symbolic",
        "input-gaming": "input-gaming-symbolic",
        "printer": "printer-symbolic",
        "multimedia-player": "multimedia-player-symbolic",
    }.get(device_type, "bluetooth-active-symbolic")


# ── Page ──────────────────────────────────────────────────────────────────────


class BluetoothPage(Gtk.Box):
    """Two-panel Bluetooth manager page."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._toast_ov = toast_overlay
        self._devices: list[BluetoothDevice] = []
        self._selected: Optional[BluetoothDevice] = None
        self._powered = False
        self._scanning = False
        self._right_panel: Gtk.Box

        self._build_ui()
        self.refresh()

    # ── UI construction ───────────────────────────────────────────────────────

    def _build_ui(self) -> None:
        # ── Toolbar ──
        toolbar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        toolbar.set_margin_start(16)
        toolbar.set_margin_end(12)
        toolbar.set_margin_top(10)
        toolbar.set_margin_bottom(6)

        title = Gtk.Label(label="Bluetooth")
        title.add_css_class("heading")
        title.set_xalign(0)
        title.set_hexpand(True)

        self._status_label = Gtk.Label(label="")
        self._status_label.add_css_class("dim-label")
        self._status_label.add_css_class("caption")

        self._spinner = Gtk.Spinner()
        self._spinner.set_visible(False)

        self._scan_btn = Gtk.Button(icon_name="edit-find-symbolic")
        self._scan_btn.add_css_class("flat")
        self._scan_btn.set_tooltip_text("Scan for nearby devices (8 s)")
        self._scan_btn.connect("clicked", self._on_scan)

        self._power_btn = Gtk.Button(icon_name="bluetooth-active-symbolic")
        self._power_btn.add_css_class("flat")
        self._power_btn.set_tooltip_text("Toggle Bluetooth power")
        self._power_btn.connect("clicked", self._on_power_toggle)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.add_css_class("flat")
        refresh_btn.set_tooltip_text("Refresh device list")
        refresh_btn.connect("clicked", lambda _: self.refresh())

        toolbar.append(title)
        toolbar.append(self._status_label)
        toolbar.append(self._spinner)
        toolbar.append(self._scan_btn)
        toolbar.append(self._power_btn)
        toolbar.append(refresh_btn)
        self.append(toolbar)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # ── Two-panel body ──
        pane = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        pane.set_vexpand(True)

        # Left — device list
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        left.set_size_request(300, -1)

        self._list = Gtk.ListBox()
        self._list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._list.add_css_class("navigation-sidebar")
        self._list.connect("row-selected", self._on_row_selected)

        list_scroll = Gtk.ScrolledWindow()
        list_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        list_scroll.set_vexpand(True)
        list_scroll.set_child(self._list)
        left.append(list_scroll)

        # Right — detail panel
        self._right_panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._right_panel.set_hexpand(True)
        self._show_detail(None)

        pane.append(left)
        pane.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        pane.append(self._right_panel)
        self.append(pane)

    # ── Detail panel ──────────────────────────────────────────────────────────

    def _clear_right(self) -> None:
        child = self._right_panel.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            self._right_panel.remove(child)
            child = nxt

    def _show_detail(self, device: Optional[BluetoothDevice]) -> None:
        self._clear_right()

        if device is None:
            placeholder = Adw.StatusPage(
                icon_name="bluetooth-active-symbolic",
                title="No Device Selected",
                description="Select a device from the list",
            )
            placeholder.set_vexpand(True)
            self._right_panel.append(placeholder)
            return

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_margin_start(20)
        box.set_margin_end(20)
        box.set_margin_top(20)
        box.set_margin_bottom(20)

        # Device icon + name
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        icon_img = Gtk.Image.new_from_icon_name(_icon_for_type(device.device_type))
        icon_img.set_pixel_size(52)
        icon_img.add_css_class("bt-device-icon")

        name_stack = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        name_lbl = Gtk.Label(label=device.display_name)
        name_lbl.add_css_class("title-2")
        name_lbl.set_xalign(0)
        name_lbl.set_wrap(True)
        addr_lbl = Gtk.Label(label=device.address)
        addr_lbl.add_css_class("dim-label")
        addr_lbl.add_css_class("caption")
        addr_lbl.set_xalign(0)
        name_stack.append(name_lbl)
        name_stack.append(addr_lbl)
        head.append(icon_img)
        head.append(name_stack)
        box.append(head)

        # Status badges
        badge_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        for label_text, css in [
            ("Connected", "bt-badge-connected") if device.connected else ("", ""),
            ("Paired", "bt-badge-paired") if device.paired else ("", ""),
            ("Trusted", "bt-badge-trusted") if device.trusted else ("", ""),
        ]:
            if label_text:
                b = Gtk.Label(label=label_text)
                b.add_css_class("manager-badge")
                b.add_css_class(css)
                badge_row.append(b)
        box.append(badge_row)

        # Action buttons
        btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        if device.connected:
            disc_btn = Gtk.Button(label="Disconnect")
            disc_btn.add_css_class("destructive-action")
            disc_btn.connect("clicked", lambda _, d=device: self._action_disconnect(d))
            btns.append(disc_btn)
        else:
            conn_btn = Gtk.Button(label="Connect")
            conn_btn.add_css_class("suggested-action")
            conn_btn.connect("clicked", lambda _, d=device: self._action_connect(d))
            btns.append(conn_btn)

        if device.paired:
            rm_btn = Gtk.Button(label="Remove")
            rm_btn.add_css_class("flat")
            rm_btn.connect("clicked", lambda _, d=device: self._action_remove(d))
            btns.append(rm_btn)

        box.append(btns)
        self._right_panel.append(box)

    # ── List population ───────────────────────────────────────────────────────

    def _make_device_row(self, device: BluetoothDevice) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row._device = device  # type: ignore[attr-defined]

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        icon = Gtk.Image.new_from_icon_name(_icon_for_type(device.device_type))
        icon.set_pixel_size(22)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        info.set_hexpand(True)

        name = Gtk.Label(label=device.display_name)
        name.set_xalign(0)
        name.set_ellipsize(Pango.EllipsizeMode.END)

        parts: list[str] = []
        if device.connected:
            parts.append("Connected")
        elif device.paired:
            parts.append("Paired")
        if device.device_type:
            parts.append(device.device_type)
        sub = Gtk.Label(label=" · ".join(parts) or device.address)
        sub.set_xalign(0)
        sub.set_ellipsize(Pango.EllipsizeMode.END)
        sub.add_css_class("dim-label")
        sub.add_css_class("caption")

        info.append(name)
        info.append(sub)
        box.append(icon)
        box.append(info)

        if device.connected:
            dot = Gtk.Image.new_from_icon_name("object-select-symbolic")
            dot.set_pixel_size(14)
            dot.add_css_class("accent")
            box.append(dot)

        row.set_child(box)
        return row

    # ── Refresh ───────────────────────────────────────────────────────────────

    def refresh(self, force: bool = False) -> None:
        self._spinner.set_visible(True)
        self._spinner.start()
        self._status_label.set_text("Refreshing…")
        threading.Thread(target=self._do_refresh, args=(force,), daemon=True).start()

    def _do_refresh(self, force: bool = False) -> None:
        powered = get_bt_powered()
        devices = get_devices(force=force) if powered else []
        GLib.idle_add(self._apply_refresh, powered, devices)

    def _apply_refresh(self, powered: bool, devices: list[BluetoothDevice]) -> bool:
        self._powered = powered
        self._devices = devices
        self._spinner.stop()
        self._spinner.set_visible(False)
        self._scan_btn.set_sensitive(powered)

        if powered:
            n_conn = sum(1 for d in devices if d.connected)
            self._status_label.set_text(
                f"{len(devices)} devices · {n_conn} connected"
            )
        else:
            self._status_label.set_text("Powered off")

        while r := self._list.get_row_at_index(0):
            self._list.remove(r)

        if not devices:
            placeholder_row = Gtk.ListBoxRow()
            placeholder_row.set_selectable(False)
            lbl = Gtk.Label(
                label="No devices found" if powered else "Bluetooth is powered off"
            )
            lbl.add_css_class("dim-label")
            lbl.set_margin_top(16)
            lbl.set_margin_bottom(16)
            placeholder_row.set_child(lbl)
            self._list.append(placeholder_row)
        else:
            for d in devices:
                self._list.append(self._make_device_row(d))

        self._show_detail(None)
        return GLib.SOURCE_REMOVE

    # ── Callbacks ─────────────────────────────────────────────────────────────

    def _on_row_selected(self, _lb: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        device = getattr(row, "_device", None) if row else None
        self._selected = device
        self._show_detail(device)

    def _on_power_toggle(self, _btn: Gtk.Button) -> None:
        threading.Thread(
            target=lambda: (set_bt_power(not self._powered), GLib.idle_add(self.refresh)),
            daemon=True,
        ).start()

    def _on_scan(self, _btn: Gtk.Button) -> None:
        if self._scanning:
            return
        self._scanning = True
        self._scan_btn.set_sensitive(False)
        self._status_label.set_text("Scanning for devices…")
        self._spinner.set_visible(True)
        self._spinner.start()
        threading.Thread(target=self._do_scan, daemon=True).start()

    def _do_scan(self) -> None:
        try:
            # Run scan for 8 seconds, then explicitly turn it off
            proc = subprocess.Popen(
                ["bluetoothctl"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            proc.stdin.write("scan on\n")
            proc.stdin.flush()
            time.sleep(8)
            proc.stdin.write("scan off\n")
            proc.stdin.flush()
            time.sleep(1)  # Give it a moment to process
            proc.terminate()
            proc.wait(timeout=2)
        except Exception as e:
            log.debug(f"Scan error: {e}")
        finally:
            self._scanning = False
            GLib.idle_add(self.refresh, True)

    def _action_connect(self, device: BluetoothDevice) -> None:
        self._status_label.set_text(f"Connecting to {device.display_name}…")
        self._spinner.set_visible(True)
        self._spinner.start()

        def _work() -> None:
            ok, out = connect_device(device.address)
            msg = f"Connected to {device.display_name}" if ok else f"Connect failed: {out[:80]}"
            GLib.idle_add(self._after_action, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _action_disconnect(self, device: BluetoothDevice) -> None:
        def _work() -> None:
            ok, out = disconnect_device(device.address)
            msg = f"Disconnected {device.display_name}" if ok else f"Disconnect failed: {out[:80]}"
            GLib.idle_add(self._after_action, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _action_remove(self, device: BluetoothDevice) -> None:
        def _work() -> None:
            ok, out = remove_device(device.address)
            msg = f"Removed {device.display_name}" if ok else f"Remove failed: {out[:80]}"
            GLib.idle_add(self._after_action, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _after_action(self, msg: str) -> bool:
        from lib import utility
        utility.toast(self._toast_ov, msg)
        self.refresh()
        return GLib.SOURCE_REMOVE
