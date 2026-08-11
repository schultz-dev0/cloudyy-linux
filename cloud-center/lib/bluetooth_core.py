"""GTK-free bluetoothctl querying and fixed Bluetooth actions."""
from __future__ import annotations

import concurrent.futures
import logging
import re
import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Any, Callable


log = logging.getLogger(__name__)

DEVICES_CACHE_TTL = 5.0
DEVICE_LINE = re.compile(r"Device\s+([\w:]+)\s+(.*)")
ADDRESS_LINE = re.compile(r"Device\s+([\w:]+)")
MAC_RE = re.compile(r"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")

ALLOWED_ACTIONS = frozenset({
    "set_power",
    "connect",
    "disconnect",
    "remove",
    "trust",
    "start_scan",
    "stop_scan",
})

ICON_BY_TYPE = {
    "audio-headset": "audio-headset-symbolic",
    "audio-headphones": "audio-headphones-symbolic",
    "phone": "phone-symbolic",
    "computer": "computer-symbolic",
    "input-keyboard": "input-keyboard-symbolic",
    "input-mouse": "input-mouse-symbolic",
    "input-gaming": "input-gaming-symbolic",
    "printer": "printer-symbolic",
    "multimedia-player": "multimedia-player-symbolic",
}


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


_devices_cache: list[BluetoothDevice] = []
_devices_cache_time: float = 0.0
_cache_lock = threading.Lock()


def _run_bt(args: list[str], timeout: int = 6) -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["bluetoothctl"] + args,
            capture_output=True, text=True, timeout=timeout,
        )
        return result.returncode == 0, (result.stdout or "") + (result.stderr or "")
    except subprocess.TimeoutExpired:
        return False, "timeout"
    except FileNotFoundError:
        return False, "bluetoothctl not found"


def parse_device_list(output: str) -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    for line in output.splitlines():
        match = DEVICE_LINE.match(line)
        if match:
            pairs.append((match.group(1), match.group(2).strip()))
    return pairs


def parse_paired_addresses(output: str) -> set[str]:
    addresses: set[str] = set()
    for line in output.splitlines():
        match = ADDRESS_LINE.match(line)
        if match:
            addresses.add(match.group(1))
    return addresses


def parse_device_info(info: str) -> dict[str, Any]:
    connected = "Connected: yes" in info
    paired = "Paired: yes" in info
    trusted = "Trusted: yes" in info
    device_type = ""
    for line in info.splitlines():
        if "Icon:" in line:
            device_type = line.split(":", 1)[1].strip()
            break
    return {
        "connected": connected,
        "paired": paired,
        "trusted": trusted,
        "device_type": device_type,
    }


def icon_for_type(device_type: str) -> str:
    return ICON_BY_TYPE.get(device_type, "bluetooth-active-symbolic")


def sort_devices(devices: list[BluetoothDevice]) -> list[BluetoothDevice]:
    return sorted(
        devices,
        key=lambda device: (
            not device.connected,
            not device.paired,
            device.display_name.lower(),
        ),
    )


def get_bt_powered() -> bool:
    _, out = _run_bt(["show"])
    return "Powered: yes" in out


def set_bt_power(on: bool) -> bool:
    ok, _ = _run_bt(["power", "on" if on else "off"])
    return ok


def invalidate_devices_cache() -> None:
    global _devices_cache, _devices_cache_time
    with _cache_lock:
        _devices_cache = []
        _devices_cache_time = 0.0


def get_devices(force: bool = False) -> list[BluetoothDevice]:
    global _devices_cache, _devices_cache_time
    with _cache_lock:
        if not force and time.monotonic() - _devices_cache_time < DEVICES_CACHE_TTL:
            return list(_devices_cache)

    _, paired_out = _run_bt(["devices", "Paired"])
    paired_addrs = parse_paired_addresses(paired_out)

    _, devices_out = _run_bt(["devices"])
    addr_name_pairs = parse_device_list(devices_out)

    def fetch_one(addr: str, name: str) -> BluetoothDevice:
        _, info = _run_bt(["info", addr])
        parsed = parse_device_info(info)
        return BluetoothDevice(
            address=addr,
            name=name,
            paired=addr in paired_addrs or parsed["paired"],
            connected=parsed["connected"],
            trusted=parsed["trusted"],
            device_type=parsed["device_type"],
        )

    results: list[BluetoothDevice] = []
    if addr_name_pairs:
        max_workers = min(4, len(addr_name_pairs))
        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = [
                pool.submit(fetch_one, addr, name) for addr, name in addr_name_pairs
            ]
            for future in concurrent.futures.as_completed(futures):
                try:
                    results.append(future.result())
                except Exception as exc:
                    log.debug("bluetooth device fetch failed: %s", exc)

    results = sort_devices(results)
    with _cache_lock:
        _devices_cache = results
        _devices_cache_time = time.monotonic()
    return list(results)


CONNECT_DROP_CHECK_DELAY = 2.0


def connect_device(address: str) -> tuple[bool, str]:
    # ponytail: BLE HID peripherals waking from sleep sometimes have their GATT
    # server fail first-read with ATT 0x0E right after connect, and bluetoothd
    # tears the link down without retrying (bluez #1911, unpatched upstream).
    # One retry covers it; raise CONNECT_DROP_CHECK_DELAY if it still flaps.
    ok, out = _run_bt(["connect", address], timeout=18)
    if not ok:
        return ok, out
    time.sleep(CONNECT_DROP_CHECK_DELAY)
    _, info = _run_bt(["info", address])
    if "Connected: yes" in info:
        return ok, out
    return _run_bt(["connect", address], timeout=18)


def disconnect_device(address: str) -> tuple[bool, str]:
    return _run_bt(["disconnect", address], timeout=10)


def remove_device(address: str) -> tuple[bool, str]:
    return _run_bt(["remove", address], timeout=8)


def trust_device(address: str, trust: bool) -> tuple[bool, str]:
    return _run_bt(["trust" if trust else "untrust", address], timeout=8)


def is_mac_address(value: str) -> bool:
    return bool(MAC_RE.match(value))


def serialize_device(device: BluetoothDevice) -> dict[str, Any]:
    return {
        "address": device.address,
        "name": device.name,
        "display_name": device.display_name,
        "paired": device.paired,
        "connected": device.connected,
        "trusted": device.trusted,
        "device_type": device.device_type,
        "icon": icon_for_type(device.device_type),
    }


def build_bluetooth_snapshot(
    *,
    scanning: bool = False,
    force: bool = False,
) -> dict[str, Any]:
    powered = get_bt_powered()
    devices = get_devices(force=force) if powered else []
    return {
        "powered": powered,
        "scanning": scanning,
        "devices": [serialize_device(device) for device in devices],
        "error": "",
    }


def run_scan_session(
    duration: float = 8.0,
    *,
    should_stop: Callable[[], bool] | None = None,
    popen: Any = subprocess.Popen,
    sleeper: Callable[[float], None] = time.sleep,
) -> tuple[bool, str]:
    """Run a timed interactive bluetoothctl scan; always turns scan off."""
    process = None
    try:
        process = popen(
            ["bluetoothctl"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if process.stdin is None:
            return False, "bluetoothctl stdin unavailable"
        process.stdin.write("scan on\n")
        process.stdin.flush()
        deadline = time.monotonic() + max(0.0, duration)
        while time.monotonic() < deadline:
            if should_stop is not None and should_stop():
                break
            sleeper(0.2)
        try:
            process.stdin.write("scan off\n")
            process.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            log.debug("bluetooth scan off failed: %s", exc)
        sleeper(0.5)
        return True, ""
    except Exception as exc:
        log.debug("bluetooth scan error: %s", exc)
        return False, str(exc)
    finally:
        if process is not None:
            try:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=2)
            except (ProcessLookupError, OSError) as exc:
                log.debug("bluetooth scan cleanup: %s", exc)
        invalidate_devices_cache()


def execute_bluetooth_action(
    action: str, target: str, value: Any,
) -> tuple[bool, str]:
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown bluetooth action: {action}")
    if action == "set_power":
        ok = set_bt_power(bool(value))
        invalidate_devices_cache()
        return ok, "" if ok else "Could not change Bluetooth power"
    if action == "start_scan":
        duration = 8.0
        if value is not None:
            try:
                duration = float(value)
            except (TypeError, ValueError) as exc:
                raise ValueError("scan duration must be a number") from exc
        return run_scan_session(duration)
    if action == "stop_scan":
        # Session ownership lives in the ccd adapter; core no-ops when called alone.
        return True, ""
    if not is_mac_address(str(target)):
        raise ValueError(f"invalid bluetooth address: {target}")
    address = str(target)
    if action == "connect":
        ok, out = connect_device(address)
    elif action == "disconnect":
        ok, out = disconnect_device(address)
    elif action == "remove":
        ok, out = remove_device(address)
    elif action == "trust":
        ok, out = trust_device(address, bool(value))
    else:  # pragma: no cover - guarded by ALLOWED_ACTIONS
        raise ValueError(f"unknown bluetooth action: {action}")
    invalidate_devices_cache()
    return ok, out
