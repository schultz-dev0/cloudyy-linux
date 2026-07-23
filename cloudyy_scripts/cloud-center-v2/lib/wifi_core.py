"""GTK-free NetworkManager (nmcli) helpers, snapshot, and fixed Wi-Fi actions."""
from __future__ import annotations

import dataclasses
import logging
import subprocess
from dataclasses import dataclass
from typing import Any


log = logging.getLogger(__name__)

ALLOWED_ACTIONS = frozenset({
    "set_radio",
    "rescan",
    "connect",
    "connect_enterprise",
    "disconnect",
    "forget",
})


@dataclass
class WifiNetwork:
    ssid: str
    bssid: str
    signal: int  # 0–100
    security: str  # "", "WPA2", "WPA3", "--", etc.
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


def run_nmcli(args: list[str], timeout: int = 10) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["nmcli"] + args,
            capture_output=True, text=True, timeout=timeout,
        )
        return result.returncode == 0, (result.stdout or "") + (result.stderr or "")
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except FileNotFoundError:
        return False, "nmcli not found"


# Back-compat alias used by wifi_page imports.
_run_nmcli = run_nmcli


def get_wifi_enabled() -> bool:
    _, out = run_nmcli(["radio", "wifi"])
    return "enabled" in out


def set_wifi_enabled(on: bool) -> bool:
    ok, _ = run_nmcli(["radio", "wifi", "on" if on else "off"])
    return ok


def get_active_ssid() -> str:
    _, out = run_nmcli(["-t", "-f", "active,ssid", "device", "wifi"])
    for line in out.splitlines():
        if line.startswith("yes:"):
            return line[4:].strip()
    return ""


def get_wifi_device() -> str:
    """Return the first Wi-Fi device name (e.g. wlan0)."""
    _, out = run_nmcli(["-t", "-f", "DEVICE,TYPE", "device"])
    for line in out.splitlines():
        parts = line.split(":", 1)
        if len(parts) == 2 and parts[1].strip() == "wifi":
            return parts[0].strip()
    return ""


_get_wifi_device = get_wifi_device


def parse_network_list(output: str) -> list[WifiNetwork]:
    """Parse multiline ``nmcli device wifi list`` output into unique SSIDs."""
    networks: list[WifiNetwork] = []
    seen_ssids: set[str] = set()
    current: dict[str, str] = {}

    def commit(record: dict[str, str]) -> None:
        ssid = record.get("SSID", "").strip()
        if not ssid or ssid == "--":
            return
        try:
            signal = int(record.get("SIGNAL", "0").strip())
        except ValueError:
            signal = 0
        connected = record.get("ACTIVE", "").strip().lower() == "yes"
        if ssid not in seen_ssids:
            seen_ssids.add(ssid)
            networks.append(WifiNetwork(
                ssid=ssid,
                bssid=record.get("BSSID", "").strip(),
                signal=signal,
                security=record.get("SECURITY", "").strip(),
                connected=connected,
                frequency=record.get("FREQ", "").strip(),
            ))
            return
        for network in networks:
            if network.ssid != ssid:
                continue
            if connected:
                network.connected = True
            if signal > network.signal:
                network.signal = signal
                network.bssid = record.get("BSSID", "").strip()
                network.security = record.get("SECURITY", "").strip()
                network.frequency = record.get("FREQ", "").strip()
            break

    for raw_line in output.splitlines():
        stripped = raw_line.strip()
        if not stripped:
            continue
        key, _, value = stripped.partition(":")
        key = key.strip()
        # A repeated key (e.g. SSID appearing again) means a new record starts.
        if key in current:
            commit(current)
            current = {}
        current[key] = value.strip()

    commit(current)
    networks.sort(key=lambda network: (not network.connected, -network.signal))
    return networks


def apply_saved_flags(networks: list[WifiNetwork], saved_output: str) -> None:
    saved_names = {line.strip() for line in saved_output.splitlines() if line.strip()}
    for network in networks:
        network.saved = network.ssid in saved_names


def list_networks() -> list[WifiNetwork]:
    """Return the current nmcli network list without forcing a rescan."""
    _, out = run_nmcli([
        "-m", "multiline",
        "-f", "SSID,BSSID,SIGNAL,SECURITY,ACTIVE,FREQ",
        "device", "wifi", "list",
    ])
    networks = parse_network_list(out)
    _, saved_out = run_nmcli(["-t", "-f", "NAME", "connection", "show"])
    apply_saved_flags(networks, saved_out)
    return networks


_list_networks = list_networks


def scan_networks() -> list[WifiNetwork]:
    """Force a Wi-Fi rescan, then return the updated network list."""
    run_nmcli(["device", "wifi", "rescan"], timeout=6)
    return list_networks()


def connect_network(ssid: str, password: str | None = None) -> tuple[bool, str]:
    if password:
        return run_nmcli(
            ["device", "wifi", "connect", ssid, "password", password], timeout=30,
        )
    # For saved connections (including 802.1x), bring up the existing profile.
    return run_nmcli(["connection", "up", ssid], timeout=30)


def get_enterprise_identity(ssid: str) -> str:
    _, out = run_nmcli(["-t", "-f", "802-1x.identity", "connection", "show", ssid])
    return out.strip()


def connect_enterprise_network(
    ssid: str, identity: str, password: str,
) -> tuple[bool, str]:
    """Connect to a WPA-Enterprise (802.1x/EAP) network like EDUROAM."""
    run_nmcli(["connection", "delete", ssid], timeout=10)

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
    device = get_wifi_device()
    if device:
        args += ["ifname", device]

    ok, out = run_nmcli(args, timeout=15)
    if not ok:
        return False, out
    return run_nmcli(["connection", "up", ssid], timeout=30)


def disconnect_network() -> tuple[bool, str]:
    device = get_wifi_device()
    if device:
        return run_nmcli(["device", "disconnect", device], timeout=10)
    return False, "No WiFi device found"


def forget_network(ssid: str) -> tuple[bool, str]:
    return run_nmcli(["connection", "delete", ssid], timeout=10)


def serialize_network(network: WifiNetwork, *, identity: str = "") -> dict[str, Any]:
    payload = dataclasses.asdict(network)
    payload["is_open"] = network.is_open
    payload["is_enterprise"] = network.is_enterprise
    payload["signal_icon"] = network.signal_icon
    payload["identity"] = identity
    return payload


def build_wifi_snapshot(*, rescan: bool = False) -> dict[str, Any]:
    enabled = get_wifi_enabled()
    if enabled:
        networks = scan_networks() if rescan else list_networks()
        active = get_active_ssid()
    else:
        networks = []
        active = ""
    serialized: list[dict[str, Any]] = []
    for network in networks:
        identity = ""
        if network.saved and network.is_enterprise:
            identity = get_enterprise_identity(network.ssid)
        serialized.append(serialize_network(network, identity=identity))
    return {
        "enabled": enabled,
        "active_ssid": active,
        "device": get_wifi_device(),
        "networks": serialized,
    }


def _require_ssid(target: Any) -> str:
    if not isinstance(target, str) or not target.strip():
        raise ValueError("ssid is required")
    return target.strip()


def _enterprise_credentials(value: Any) -> tuple[str, str]:
    if not isinstance(value, dict):
        raise ValueError("enterprise credentials must be an object")
    identity = value.get("identity")
    password = value.get("password")
    if not isinstance(identity, str) or not identity.strip():
        raise ValueError("identity is required")
    if not isinstance(password, str) or not password:
        raise ValueError("password is required")
    return identity.strip(), password


def execute_wifi_action(action: str, target: str, value: Any) -> tuple[bool, str]:
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown wifi action: {action}")

    if action == "set_radio":
        if not isinstance(value, bool):
            raise ValueError("radio value must be a boolean")
        ok = set_wifi_enabled(value)
        return ok, "" if ok else "Could not change Wi-Fi radio"

    if action == "rescan":
        try:
            scan_networks()
        except Exception as exc:
            return False, str(exc)
        return True, ""

    if action == "connect":
        ssid = _require_ssid(target)
        password = None
        if value is not None and value != "":
            if not isinstance(value, str):
                raise ValueError("password must be a string")
            password = value
        return connect_network(ssid, password)

    if action == "connect_enterprise":
        ssid = _require_ssid(target)
        identity, password = _enterprise_credentials(value)
        return connect_enterprise_network(ssid, identity, password)

    if action == "disconnect":
        return disconnect_network()

    if action == "forget":
        return forget_network(_require_ssid(target))

    raise ValueError(f"unknown wifi action: {action}")
