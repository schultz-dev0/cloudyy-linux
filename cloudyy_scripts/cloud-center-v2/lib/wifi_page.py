"""Cloud Center — Wi-Fi manager page using nmcli."""
from __future__ import annotations

import logging
import subprocess
import threading
from dataclasses import dataclass
from typing import Optional

from gi.repository import Adw, GLib, Gtk, Pango

log = logging.getLogger(__name__)


# ── Data model ────────────────────────────────────────────────────────────────


@dataclass
class WifiNetwork:
    ssid: str
    bssid: str
    signal: int       # 0–100
    security: str     # "", "WPA2", "WPA3", "--", etc.
    connected: bool = False
    saved: bool = False
    frequency: str = ""

    @property
    def signal_icon(self) -> str:
        if self.signal >= 75:
            return "network-wireless-signal-excellent-symbolic"
        if self.signal >= 50:
            return "network-wireless-signal-good-symbolic"
        if self.signal >= 25:
            return "network-wireless-signal-ok-symbolic"
        return "network-wireless-signal-weak-symbolic"

    @property
    def is_open(self) -> bool:
        return not self.security or self.security in ("--", "")

    @property
    def is_enterprise(self) -> bool:
        return "802.1X" in self.security


# ── nmcli helpers ─────────────────────────────────────────────────────────────


def _run_nmcli(args: list[str], timeout: int = 10) -> tuple[bool, str]:
    try:
        r = subprocess.run(
            ["nmcli"] + args,
            capture_output=True, text=True, timeout=timeout,
        )
        return r.returncode == 0, r.stdout + r.stderr
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except FileNotFoundError:
        return False, "nmcli not found"


def get_wifi_enabled() -> bool:
    _, out = _run_nmcli(["radio", "wifi"])
    return "enabled" in out


def set_wifi_enabled(on: bool) -> bool:
    ok, _ = _run_nmcli(["radio", "wifi", "on" if on else "off"])
    return ok


def get_active_ssid() -> str:
    _, out = _run_nmcli(["-t", "-f", "active,ssid", "device", "wifi"])
    for line in out.splitlines():
        if line.startswith("yes:"):
            return line[4:].strip()
    return ""


def _get_wifi_device() -> str:
    """Return the first WiFi device name (e.g. wlan0)."""
    _, out = _run_nmcli(["-t", "-f", "DEVICE,TYPE", "device"])
    for line in out.splitlines():
        parts = line.split(":", 1)
        if len(parts) == 2 and parts[1].strip() == "wifi":
            return parts[0].strip()
    return ""


def _list_networks() -> list[WifiNetwork]:
    """Return the current nmcli network list without forcing a rescan."""
    _, out = _run_nmcli([
        "-m", "multiline",
        "-f", "SSID,BSSID,SIGNAL,SECURITY,ACTIVE,FREQ",
        "device", "wifi", "list",
    ])

    networks: list[WifiNetwork] = []
    seen_ssids: set[str] = set()
    current: dict[str, str] = {}

    def _commit(record: dict[str, str]) -> None:
        ssid = record.get("SSID", "").strip()
        if not ssid or ssid == "--":
            return
        try:
            sig = int(record.get("SIGNAL", "0").strip())
        except ValueError:
            sig = 0
        if ssid not in seen_ssids:
            seen_ssids.add(ssid)
            networks.append(WifiNetwork(
                ssid=ssid,
                bssid=record.get("BSSID", "").strip(),
                signal=sig,
                security=record.get("SECURITY", "").strip(),
                connected=record.get("ACTIVE", "").strip().lower() == "yes",
                frequency=record.get("FREQ", "").strip(),
            ))
        else:
            for n in networks:
                if n.ssid == ssid and sig > n.signal:
                    n.signal = sig

    for raw_line in out.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        key, _, value = stripped.partition(":")
        key = key.strip()
        # A repeated key (e.g. SSID appearing again) means a new record starts
        if key in current:
            _commit(current)
            current = {}
        current[key] = value.strip()

    _commit(current)

    # Mark saved connections
    _, saved_out = _run_nmcli(["-t", "-f", "NAME", "connection", "show"])
    saved_names = {line.strip() for line in saved_out.splitlines()}
    for n in networks:
        n.saved = n.ssid in saved_names

    networks.sort(key=lambda n: (not n.connected, -n.signal))
    return networks


def scan_networks() -> list[WifiNetwork]:
    """Force a Wi-Fi rescan, then return the updated network list."""
    _run_nmcli(["device", "wifi", "rescan"], timeout=6)
    return _list_networks()


def connect_network(ssid: str, password: str | None = None) -> tuple[bool, str]:
    if password:
        return _run_nmcli(["device", "wifi", "connect", ssid, "password", password], timeout=30)
    # For saved connections (including 802.1x), bring up the existing profile directly
    return _run_nmcli(["connection", "up", ssid], timeout=30)


def get_enterprise_identity(ssid: str) -> str:
    _, out = _run_nmcli(["-t", "-f", "802-1x.identity", "connection", "show", ssid])
    return out.strip()


def connect_enterprise_network(ssid: str, identity: str, password: str) -> tuple[bool, str]:
    """Connect to a WPA-Enterprise (802.1x/EAP) network like EDUROAM."""
    _run_nmcli(["connection", "delete", ssid], timeout=10)

    args = [
        "connection", "add",
        "type", "wifi",
        "con-name", ssid,
        "ssid", ssid,
        "wifi-sec.key-mgmt", "wpa-eap",
        "802-1x.eap", "peap",
        "802-1x.identity", identity,
        "802-1x.phase2-auth", "mschapv2",
        "802-1x.password", password,
    ]
    dev = _get_wifi_device()
    if dev:
        args += ["ifname", dev]

    ok, out = _run_nmcli(args, timeout=15)
    if not ok:
        return False, out

    return _run_nmcli(["connection", "up", ssid], timeout=30)


def disconnect_network() -> tuple[bool, str]:
    dev = _get_wifi_device()
    if dev:
        return _run_nmcli(["device", "disconnect", dev], timeout=10)
    return False, "No WiFi device found"


def forget_network(ssid: str) -> tuple[bool, str]:
    return _run_nmcli(["connection", "delete", ssid], timeout=10)


# ── Password dialog ───────────────────────────────────────────────────────────


class _PasswordDialog(Adw.Dialog):
    def __init__(self, ssid: str, on_connect) -> None:
        super().__init__()
        self._ssid = ssid
        self._on_connect = on_connect
        self.set_title(f"Connect to {ssid}")
        self.set_content_width(420)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _: self.close())
        header.pack_start(cancel_btn)
        self._conn_btn = Gtk.Button(label="Connect")
        self._conn_btn.add_css_class("suggested-action")
        self._conn_btn.connect("clicked", self._on_clicked)
        header.pack_end(self._conn_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(16)
        content.set_margin_bottom(16)

        info = Gtk.Label(label=f'Enter the password for "{ssid}"')
        info.set_wrap(True)
        content.append(info)

        self._pw_row = Adw.EntryRow(title="Password")
        self._pw_row.set_input_purpose(Gtk.InputPurpose.PASSWORD)

        # Toggle visibility button
        self._vis_btn = Gtk.ToggleButton(icon_name="view-reveal-symbolic")
        self._vis_btn.add_css_class("flat")
        self._vis_btn.set_valign(Gtk.Align.CENTER)
        self._vis_btn.connect("toggled", self._on_vis_toggled)
        self._pw_row.add_suffix(self._vis_btn)
        self._pw_row.connect("entry-activated", lambda _: self._on_clicked(None))
        # Default: hide password (use a GtkEntry visibility trick)
        self._pw_row.set_show_apply_button(False)

        grp = Adw.PreferencesGroup()
        grp.add(self._pw_row)
        content.append(grp)

        toolbar.set_content(content)
        self.set_child(toolbar)

    def _on_vis_toggled(self, btn: Gtk.ToggleButton) -> None:
        # AdwEntryRow doesn't expose visibility directly; we find its internal GtkText
        text_widget = self._find_text_child(self._pw_row)
        if text_widget:
            text_widget.set_visibility(btn.get_active())

    def _find_text_child(self, parent: Gtk.Widget) -> Optional[Gtk.Text]:
        child = parent.get_first_child()
        while child:
            if isinstance(child, Gtk.Text):
                return child
            found = self._find_text_child(child)
            if found:
                return found
            child = child.get_next_sibling()
        return None

    def _on_clicked(self, _btn) -> None:
        pw = self._pw_row.get_text()
        if self._on_connect:
            self._on_connect(self._ssid, pw)
        self.close()


# ── Enterprise (802.1x) dialog ────────────────────────────────────────────────


class _EnterpriseDialog(Adw.Dialog):
    def __init__(self, ssid: str, on_connect, prefill_identity: str = "") -> None:
        super().__init__()
        self._ssid = ssid
        self._on_connect = on_connect
        self.set_title(f"Connect to {ssid}")
        self.set_content_width(420)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda _: self.close())
        header.pack_start(cancel_btn)
        self._conn_btn = Gtk.Button(label="Connect")
        self._conn_btn.add_css_class("suggested-action")
        self._conn_btn.connect("clicked", self._on_clicked)
        header.pack_end(self._conn_btn)
        toolbar.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(16)
        content.set_margin_end(16)
        content.set_margin_top(16)
        content.set_margin_bottom(16)

        info = Gtk.Label(label=f'"{ssid}" requires a username and password (WPA Enterprise)')
        info.set_wrap(True)
        content.append(info)

        grp = Adw.PreferencesGroup()

        self._id_row = Adw.EntryRow(title="Username (e.g. user@university.edu)")
        if prefill_identity:
            self._id_row.set_text(prefill_identity)
        self._id_row.connect("entry-activated", lambda _: self._pw_row.grab_focus())
        grp.add(self._id_row)

        self._pw_row = Adw.EntryRow(title="Password")
        self._pw_row.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        self._vis_btn = Gtk.ToggleButton(icon_name="view-reveal-symbolic")
        self._vis_btn.add_css_class("flat")
        self._vis_btn.set_valign(Gtk.Align.CENTER)
        self._vis_btn.connect("toggled", self._on_vis_toggled)
        self._pw_row.add_suffix(self._vis_btn)
        self._pw_row.connect("entry-activated", lambda _: self._on_clicked(None))
        self._pw_row.connect("realize", self._hide_password_on_realize)
        grp.add(self._pw_row)

        content.append(grp)
        toolbar.set_content(content)
        self.set_child(toolbar)

    def _hide_password_on_realize(self, _widget) -> None:
        text = self._find_text_child(self._pw_row)
        if text:
            text.set_visibility(False)

    def _on_vis_toggled(self, btn: Gtk.ToggleButton) -> None:
        text_widget = self._find_text_child(self._pw_row)
        if text_widget:
            text_widget.set_visibility(btn.get_active())

    def _find_text_child(self, parent: Gtk.Widget) -> Optional[Gtk.Text]:
        child = parent.get_first_child()
        while child:
            if isinstance(child, Gtk.Text):
                return child
            found = self._find_text_child(child)
            if found:
                return found
            child = child.get_next_sibling()
        return None

    def _on_clicked(self, _btn) -> None:
        identity = self._id_row.get_text().strip()
        password = self._pw_row.get_text()
        if not identity or not password:
            return
        if self._on_connect:
            self._on_connect(self._ssid, identity, password)
        self.close()


# ── Page ──────────────────────────────────────────────────────────────────────


class WiFiPage(Gtk.Box):
    """Two-panel Wi-Fi network manager page."""

    def __init__(self, toast_overlay: Adw.ToastOverlay) -> None:
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self._toast_ov = toast_overlay
        self._networks: list[WifiNetwork] = []
        self._selected: Optional[WifiNetwork] = None
        self._wifi_enabled = False
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

        title = Gtk.Label(label="Wi-Fi")
        title.add_css_class("heading")
        title.set_xalign(0)
        title.set_hexpand(True)

        self._status_label = Gtk.Label(label="")
        self._status_label.add_css_class("dim-label")
        self._status_label.add_css_class("caption")

        self._spinner = Gtk.Spinner()
        self._spinner.set_visible(False)

        self._scan_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        self._scan_btn.add_css_class("flat")
        self._scan_btn.set_tooltip_text("Rescan networks")
        self._scan_btn.connect("clicked", lambda _: self.refresh(rescan=True))

        self._toggle_btn = Gtk.Button(icon_name="network-wireless-symbolic")
        self._toggle_btn.add_css_class("flat")
        self._toggle_btn.set_tooltip_text("Toggle Wi-Fi radio")
        self._toggle_btn.connect("clicked", self._on_toggle)

        toolbar.append(title)
        toolbar.append(self._status_label)
        toolbar.append(self._spinner)
        toolbar.append(self._scan_btn)
        toolbar.append(self._toggle_btn)
        self.append(toolbar)
        self.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))

        # ── Two-panel body ──
        pane = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        pane.set_vexpand(True)

        # Left — network list
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        left.set_size_request(300, -1)

        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Search networks…")
        self._search.set_margin_start(10)
        self._search.set_margin_end(10)
        self._search.set_margin_top(8)
        self._search.set_margin_bottom(6)
        self._search.connect("search-changed", self._on_search)
        left.append(self._search)

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

    def _show_detail(self, network: Optional[WifiNetwork]) -> None:
        self._clear_right()

        if network is None:
            placeholder = Adw.StatusPage(
                icon_name="network-wireless-symbolic",
                title="No Network Selected",
                description="Select a network to connect or manage",
            )
            placeholder.set_vexpand(True)
            self._right_panel.append(placeholder)
            return

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        box.set_margin_start(20)
        box.set_margin_end(20)
        box.set_margin_top(20)
        box.set_margin_bottom(20)

        # Network icon + name
        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        icon_img = Gtk.Image.new_from_icon_name(network.signal_icon)
        icon_img.set_pixel_size(52)

        name_stack = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        name_lbl = Gtk.Label(label=network.ssid)
        name_lbl.add_css_class("title-2")
        name_lbl.set_xalign(0)
        name_lbl.set_wrap(True)

        detail_parts: list[str] = [f"Signal: {network.signal}%"]
        if network.frequency:
            detail_parts.append(network.frequency)
        if network.security and network.security != "--":
            detail_parts.append(network.security)
        detail_lbl = Gtk.Label(label="  ·  ".join(detail_parts))
        detail_lbl.add_css_class("dim-label")
        detail_lbl.add_css_class("caption")
        detail_lbl.set_xalign(0)
        name_stack.append(name_lbl)
        name_stack.append(detail_lbl)
        head.append(icon_img)
        head.append(name_stack)
        box.append(head)

        # Badges
        badge_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        if network.connected:
            b = Gtk.Label(label="Connected")
            b.add_css_class("manager-badge")
            b.add_css_class("wifi-badge-connected")
            badge_row.append(b)
        if network.saved:
            b = Gtk.Label(label="Saved")
            b.add_css_class("manager-badge")
            b.add_css_class("wifi-badge-saved")
            badge_row.append(b)
        if not network.is_open:
            b = Gtk.Label(label=network.security or "Secured")
            b.add_css_class("manager-badge")
            b.add_css_class("wifi-badge-secured")
            badge_row.append(b)
        else:
            b = Gtk.Label(label="Open")
            b.add_css_class("manager-badge")
            b.add_css_class("wifi-badge-open")
            badge_row.append(b)
        box.append(badge_row)

        # Action buttons
        btns = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        if network.connected:
            disc_btn = Gtk.Button(label="Disconnect")
            disc_btn.add_css_class("destructive-action")
            disc_btn.connect("clicked", lambda _: self._action_disconnect())
            btns.append(disc_btn)
        else:
            conn_btn = Gtk.Button(label="Connect")
            conn_btn.add_css_class("suggested-action")
            conn_btn.connect("clicked", lambda _, n=network: self._try_connect(n))
            btns.append(conn_btn)

        if network.saved and not network.connected:
            forget_btn = Gtk.Button(label="Forget")
            forget_btn.add_css_class("flat")
            forget_btn.connect("clicked", lambda _, n=network: self._action_forget(n))
            btns.append(forget_btn)

        box.append(btns)
        self._right_panel.append(box)

    # ── List row ──────────────────────────────────────────────────────────────

    def _make_network_row(self, network: WifiNetwork) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row._network = network  # type: ignore[attr-defined]

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_start(12)
        box.set_margin_end(12)
        box.set_margin_top(8)
        box.set_margin_bottom(8)

        icon = Gtk.Image.new_from_icon_name(network.signal_icon)
        icon.set_pixel_size(20)

        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        info.set_hexpand(True)

        name = Gtk.Label(label=network.ssid)
        name.set_xalign(0)
        name.set_ellipsize(Pango.EllipsizeMode.END)

        sub_parts: list[str] = []
        if network.connected:
            sub_parts.append("Connected")
        if not network.is_open:
            sub_parts.append(network.security)
        if network.frequency:
            sub_parts.append(network.frequency)
        sub = Gtk.Label(label=" · ".join(sub_parts) if sub_parts else "Open network")
        sub.set_xalign(0)
        sub.add_css_class("dim-label")
        sub.add_css_class("caption")
        sub.set_ellipsize(Pango.EllipsizeMode.END)

        info.append(name)
        info.append(sub)
        box.append(icon)
        box.append(info)

        if network.connected:
            check = Gtk.Image.new_from_icon_name("object-select-symbolic")
            check.set_pixel_size(14)
            check.add_css_class("accent")
            box.append(check)

        row.set_child(box)
        return row

    # ── Refresh ───────────────────────────────────────────────────────────────

    def refresh(self, rescan: bool = False) -> None:
        self._spinner.set_visible(True)
        self._spinner.start()
        self._status_label.set_text("Scanning…" if rescan else "Loading…")
        self._scan_btn.set_sensitive(False)
        threading.Thread(target=self._do_refresh, args=(rescan,), daemon=True).start()

    def _do_refresh(self, rescan: bool = False) -> None:
        enabled = get_wifi_enabled()
        if enabled:
            networks = scan_networks() if rescan else _list_networks()
            active = get_active_ssid()
        else:
            networks = []
            active = ""
        GLib.idle_add(self._apply_refresh, enabled, networks, active)

    def _apply_refresh(self, enabled: bool, networks: list[WifiNetwork], active: str) -> bool:
        self._wifi_enabled = enabled
        self._networks = networks
        self._spinner.stop()
        self._spinner.set_visible(False)
        self._scan_btn.set_sensitive(True)

        if enabled:
            if active:
                self._status_label.set_text(f"Connected to {active}  ·  {len(networks)} visible")
            else:
                self._status_label.set_text(f"{len(networks)} networks visible")
        else:
            self._status_label.set_text("Wi-Fi disabled")

        self._refilter()
        return GLib.SOURCE_REMOVE

    def _on_search(self, _entry: Gtk.SearchEntry) -> None:
        self._refilter()

    def _refilter(self) -> None:
        q = self._search.get_text().strip().lower()
        filtered = (
            [n for n in self._networks if not q or q in n.ssid.lower()]
            if self._networks else []
        )

        while r := self._list.get_row_at_index(0):
            self._list.remove(r)

        if not self._wifi_enabled:
            self._add_placeholder_row("Wi-Fi is disabled")
        elif not filtered:
            self._add_placeholder_row(f"No results for '{q}'" if q else "No networks found")
        else:
            for n in filtered:
                self._list.append(self._make_network_row(n))

        self._show_detail(None)

    def _add_placeholder_row(self, text: str) -> None:
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        lbl = Gtk.Label(label=text)
        lbl.add_css_class("dim-label")
        lbl.set_margin_top(16)
        lbl.set_margin_bottom(16)
        row.set_child(lbl)
        self._list.append(row)

    # ── Callbacks ─────────────────────────────────────────────────────────────

    def _on_row_selected(self, _lb: Gtk.ListBox, row: Gtk.ListBoxRow | None) -> None:
        network = getattr(row, "_network", None) if row else None
        self._selected = network
        self._show_detail(network)

    def _on_toggle(self, _btn: Gtk.Button) -> None:
        threading.Thread(
            target=lambda: (
                set_wifi_enabled(not self._wifi_enabled),
                GLib.idle_add(self.refresh),
            ),
            daemon=True,
        ).start()

    def _try_connect(self, network: WifiNetwork) -> None:
        if network.is_enterprise:
            prefill = get_enterprise_identity(network.ssid) if network.saved else ""
            dialog = _EnterpriseDialog(
                ssid=network.ssid,
                on_connect=self._action_connect_enterprise,
                prefill_identity=prefill,
            )
            dialog.present(self.get_root())
        elif network.saved or network.is_open:
            self._action_connect(network.ssid, None)
        else:
            dialog = _PasswordDialog(
                ssid=network.ssid,
                on_connect=self._action_connect,
            )
            dialog.present(self.get_root())

    def _action_connect(self, ssid: str, password: str | None) -> None:
        self._status_label.set_text(f"Connecting to {ssid}…")
        self._spinner.set_visible(True)
        self._spinner.start()

        def _work() -> None:
            ok, out = connect_network(ssid, password or None)
            msg = f"Connected to {ssid}" if ok else f"Failed: {out.strip()[:120]}"
            GLib.idle_add(self._after_action, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _action_connect_enterprise(self, ssid: str, identity: str, password: str) -> None:
        self._status_label.set_text(f"Connecting to {ssid}…")
        self._spinner.set_visible(True)
        self._spinner.start()

        def _work() -> None:
            ok, out = connect_enterprise_network(ssid, identity, password)
            msg = f"Connected to {ssid}" if ok else f"Failed: {out.strip()[:120]}"
            GLib.idle_add(self._after_action, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _action_disconnect(self) -> None:
        def _work() -> None:
            ok, out = disconnect_network()
            msg = "Disconnected" if ok else f"Disconnect failed: {out[:80]}"
            GLib.idle_add(self._after_action, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _action_forget(self, network: WifiNetwork) -> None:
        def _work() -> None:
            ok, out = forget_network(network.ssid)
            msg = f"Forgotten {network.ssid}" if ok else f"Failed: {out[:80]}"
            GLib.idle_add(self._after_action, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _after_action(self, msg: str) -> bool:
        from lib import utility
        utility.toast(self._toast_ov, msg)
        self.refresh()
        return GLib.SOURCE_REMOVE
