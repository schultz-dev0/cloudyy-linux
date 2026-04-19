#!/usr/bin/env python3
"""
peripheral_battery.py — Waybar peripheral battery monitor

Reads battery levels from 2.4GHz and Bluetooth wireless peripherals and
outputs a single Waybar JSON object.

Requirements:
  - python-evdev  (pacman -S python-evdev)
  - python-dbus   (pacman -S python-dbus)       ← usually pre-installed
  - User in 'input' group for /dev/input access:
      sudo usermod -aG input $USER   (then re-login)

Output format (Waybar custom module with return-type: json):
  text    — icon of lowest-battery device + its percentage
  tooltip — per-device table with name, level, and fill bar
  class   — normal | warning (≤30%) | critical (≤15%) | unavailable
"""

import fcntl
import json
import os
import re
import sys
import time
from pathlib import Path

# ── Nerd Font MD icons ────────────────────────────────────────────────────────
ICON_KEYBOARD = "󰌌"   # 󰌌  nf-md-keyboard_outline
ICON_HEADSET  = "󰋋"   # 󰋋  nf-md-headset
ICON_MOUSE    = "󰍽"   # 󰍺  nf-md-mouse
ICON_EARBUDS  = "󱡏"   # 󱡏  nf-md-earbuds

# ── 2.4GHz devices to watch via the evdev HID battery axis (ABS_MISC) ────────
# Add/remove entries here as needed: (vendor_id, product_id, display_name, icon)
# ABS_MISC (axis 40) carries HID Battery Strength in the Linux kernel HID driver
ABS_MISC = 40

WARN_PCT     = 30
CRITICAL_PCT = 15

# Feature report IDs to probe as generic fallback, in priority order.
_FEATURE_IDS = [0x06, 0x04, 0x05, 0x03, 0x02, 0x01]


def _output_mode() -> str:
    """Return output mode: full | icon | percent."""
    args = {a.strip().lower() for a in sys.argv[1:]}
    if "--icon" in args:
        return "icon"
    if "--percent" in args or "--pct" in args:
        return "percent"
    return "full"


# ── Per-chipset feature-report decoders ───────────────────────────────────────
#
# Each decoder receives the raw bytes of one feature-report response (including
# byte[0] = report_id) and returns (pct: int|None, is_charging: bool).
# Return (None, False) when the report doesn't contain battery data.

def _decode_cx_rk(buf: bytearray):
        """
        CX 2.4G Wireless Receiver (VID 0x3554 / PID 0xFA09) — report 0x06

        Confirmed layout (8 bytes total including report ID):
            [0]  report_id  = 0x06
            [1]  0x00       always zero
            [2]  0x02       always 2 (subcommand?)
            [3]  0x00       always zero
            [4]  status byte (e.g. 0xe3)
            [5]  0x00
            [6]  flags byte  (0x83 observed at 100% without USB-C — meaning TBD)
            [7]  battery level on 0-63 scale  (0x3F = 63 = 100%)

        Scale confirmed: 0x3F (63) = maximum = 100%.

        Charging detection: NOT yet confirmed.
        To verify, plug in the USB-C cable and run:
            python3 -c "
            import fcntl, os
            def F(n): return (3<<30)|(n<<16)|(ord('H')<<8)|7
            fd=os.open('/dev/hidraw11', os.O_RDWR)
            b=bytearray(65); b[0]=6
            fcntl.ioctl(fd, F(65), b, True); os.close(fd)
            print([hex(x) for x in b[:8]])
            "
        Note which bytes differ from [0x06,0x00,0x02,0x00,0xe3,0x00,0x83,0x3f]
        and update this decoder accordingly.
        """
        if buf[0] != 0x06 or len(buf) < 8:
                return None, False
        raw_level = buf[7]
        if raw_level == 0:
                return None, False
        pct = round(raw_level / 63 * 100)
        pct = min(100, max(1, pct))
        # is_charging intentionally left False until byte layout is verified
        return pct, False


# ── 2.4GHz devices to watch ───────────────────────────────────────────────────
# Each entry: (vendor_id, product_id, display_name, icon, feature_decoder|None)
# feature_decoder: fn(buf) -> (pct|None, is_charging:bool)
#   None → use generic heuristic (first byte in [5, 100])
#
# ❯ HOW TO ADD YOUR OWN DEVICE ❮  (Easy 3-step process)
#
# STEP 1: Find your device's IDs
#   $ lsusb | grep "your-device-name"
#   Look for the ID like "3554:fa09"
#
# STEP 2: Pick an icon from Nerd Font cheat sheet
#   Visit: https://www.nerdfonts.com/cheat-sheet
#   Search for icon (e.g. "gamepad") → Click to copy
#
# STEP 3: Add a line to EVDEV_TARGETS below
#   Format: (0xVVVV, 0xPPPP, "My Device", "icon_glyph_or_variable", None)
#   Example: (0x1234, 0x5678, "My Gamepad", " ", None)
#
# Then test: $ python3 waybar/peripheral_battery.py
#
EVDEV_TARGETS = [
    # (0x3554, 0xFA09, "RK L75", ICON_KEYBOARD, _decode_cx_rk),  # CX receiver returns static 0x3f — no real battery data
    (0x1B1C, 0x0A97, "Corsair HS80", ICON_HEADSET,  None),
]


# ── Bluetooth devices (BlueZ Battery1) ───────────────────────────────────────
#
# This script already reads ALL Bluetooth devices that expose a battery.
# You can keep BT_TARGETS empty for auto-detection.
#
# Optional: keep public/safe examples here (no real MAC addresses).
# For private real addresses, use BT_TARGETS_LOCAL_PATH JSON instead.
#
# Local JSON file format (list):
# [
#   {"address": "AA:BB:CC:DD:EE:FF", "name": "Pebble M350s", "icon": "ICON_MOUSE"},
#   {"address": "11:22:33:44:55:66", "name": "AirPods Pro",  "icon": "ICON_EARBUDS"}
# ]
#
# `icon` in local JSON can be one of:
#   "ICON_MOUSE", "ICON_HEADSET", "ICON_KEYBOARD", "ICON_EARBUDS", or a direct glyph.
BT_TARGETS = [
    # Safe example (placeholder only):
    # {"address": "AA:BB:CC:DD:EE:FF", "name": "My Earbuds", "icon": ICON_EARBUDS},
]

BT_TARGETS_LOCAL_PATH = Path(
    os.environ.get(
        "PERIPHERAL_BATTERY_BT_TARGETS_FILE",
        str(Path.home() / ".config" / "cloudyy" / "peripheral_battery.bt_targets.json"),
    )
)


def _hidiocgfeature(length: int) -> int:
    """ioctl number for HIDIOCGFEATURE(len) = _IOWR('H', 7, char[len])."""
    return (3 << 30) | (length << 16) | (ord('H') << 8) | 7


# ── evdev / 2.4GHz helpers ────────────────────────────────────────────────────

def _parse_input_devices():
    """Parse /proc/bus/input/devices → list of dicts with vendor/product/event/sysfs/bits."""
    devices = []
    current = {}
    try:
        with open("/proc/bus/input/devices") as f:
            for raw in f:
                line = raw.rstrip("\n")
                if not line.strip():
                    if current:
                        devices.append(current)
                        current = {}
                    continue
                if len(line) < 3:
                    continue
                prefix  = line[0]
                content = line[3:]
                if prefix == "I":
                    m = re.search(r"Vendor=([0-9a-fA-F]+)\s+Product=([0-9a-fA-F]+)", content)
                    if m:
                        current["vendor"]  = int(m.group(1), 16)
                        current["product"] = int(m.group(2), 16)
                elif prefix == "S":
                    m = re.search(r"Sysfs=(\S+)", content)
                    if m:
                        current["sysfs"] = m.group(1)
                elif prefix == "H":
                    handlers = re.findall(r"event\d+", content)
                    if handlers:
                        current["event"] = "/dev/input/" + handlers[0]
                elif prefix == "B":
                    kv = content.split("=", 1)
                    if len(kv) == 2:
                        try:
                            current.setdefault("bits", {})[kv[0].strip()] = int(kv[1].strip(), 16)
                        except ValueError:
                            pass
    except OSError:
        pass
    if current:
        devices.append(current)
    return devices


def _has_abs_misc(dev) -> bool:
    """Return True when the device reports ABS_MISC (bit 40 = HID battery strength)."""
    return bool(dev.get("bits", {}).get("ABS", 0) & (1 << ABS_MISC))


def _hidraw_from_sysfs(sysfs_path: str):
    """
    Given a sysfs input path like
      /devices/pci.../0003:3554:FA09.001B/input/inputN
    navigate up to the HID device node and return the associated /dev/hidrawN,
    or None if not found.
    """
    m = re.match(
        r"(/devices/.+/[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\.[0-9A-Fa-f]+)",
        sysfs_path,
    )
    if not m:
        return None
    hidraw_dir = "/sys" + m.group(1) + "/hidraw"
    try:
        names = [n for n in os.listdir(hidraw_dir) if n.startswith("hidraw")]
        if names:
            return "/dev/" + names[0]
    except OSError:
        pass
    return None


def _probe_feature_report(hidraw_path: str, decoder):
    """
    Send HIDIOCGFEATURE (USB GET_REPORT) to the hidraw device.
    Returns (pct: int|None, is_charging: bool).

    If a device-specific decoder is provided it is used; otherwise a generic
    heuristic probes all _FEATURE_IDS and treats the first byte in [5, 100]
    as a raw percentage (best-effort for unknown chipsets).
    """
    BUF_SIZE = 65
    try:
        fd = os.open(hidraw_path, os.O_RDWR)
    except OSError:
        return None, False
    try:
        if decoder is not None:
            for report_id in [0x06] + [r for r in _FEATURE_IDS if r != 0x06]:
                try:
                    buf    = bytearray(BUF_SIZE)
                    buf[0] = report_id
                    fcntl.ioctl(fd, _hidiocgfeature(BUF_SIZE), buf, True)
                    pct, charging = decoder(buf)
                    if pct is not None:
                        return pct, charging
                except OSError:
                    continue
        else:
            for report_id in _FEATURE_IDS:
                try:
                    buf    = bytearray(BUF_SIZE)
                    buf[0] = report_id
                    fcntl.ioctl(fd, _hidiocgfeature(BUF_SIZE), buf, True)
                    for i in range(1, 16):
                        val = buf[i]
                        if 5 <= val <= 100:
                            return val, False
                except OSError:
                    continue
    finally:
        os.close(fd)
    return None, False


def _read_abs_misc(event_path: str):
    """
    Read the kernel's cached ABS_MISC value from evdev absinfo.
    Returns % or None.  Values ≤ 1 are rejected as uninitialized kernel defaults
    (the kernel sets the axis to its logical minimum before the device ever sends
    an HID battery report, so 0 or 1 are meaningless, not real battery levels).
    """
    try:
        import evdev
        device = evdev.InputDevice(event_path)
        info   = device.absinfo(ABS_MISC)
        device.close()
        if info is None or info.value <= 1:
            return None
        return min(100, info.value)
    except Exception:
        return None


def get_evdev_batteries():
    """
    Return [(name, icon, pct|None)] for all reachable 2.4GHz targets.

    Reading priority:
      1. HIDIOCGFEATURE via hidraw  — actively requests fresh data from the device
      2. evdev ABS_MISC absinfo     — kernel's cached last-seen value (may be stale
                                      if device hasn't sent a battery report yet)
    """
    all_devs = _parse_input_devices()
    results  = []
    for vid, pid, display_name, icon, decoder in EVDEV_TARGETS:
        # Secondary HID interface: same VID:PID, exposed ABS_MISC
        candidates = [
            d for d in all_devs
            if d.get("vendor") == vid
            and d.get("product") == pid
            and _has_abs_misc(d)
            and "event" in d
        ]
        if not candidates:
            continue   # dongle not connected — skip entirely

        iface = candidates[0]
        pct         = None
        is_charging = False

        # ── Primary: HIDIOCGFEATURE (sends GET_REPORT to device — always fresh)
        hidraw = _hidraw_from_sysfs(iface.get("sysfs", ""))
        if hidraw:
            pct, is_charging = _probe_feature_report(hidraw, decoder)

        # ── Fallback: evdev absinfo cached value (valid if device sent report earlier)
        if pct is None:
            pct = _read_abs_misc(iface["event"])

        results.append((display_name, icon, pct, is_charging))
    return results


# ── Bluetooth / D-Bus helpers ─────────────────────────────────────────────────

def _bt_icon(name: str) -> str:
    """Heuristic: pick icon from device name."""
    lc = name.lower()
    if any(w in lc for w in ("mouse", "pebble", "m350", "mx ", "trackball", "rat")):
        return ICON_MOUSE
    if any(w in lc for w in ("airpod", "earbud", "earbuds", "bud", "pods")):
        return ICON_EARBUDS
    if any(w in lc for w in ("headset", "earphone", "hs80", "headphone")):
        return ICON_HEADSET
    return ICON_KEYBOARD


def _looks_like_bt_peripheral(name: str, uuids) -> bool:
    """Best-effort filter for connected BT peripherals when Battery1 is absent."""
    lc = name.lower()
    if any(
        w in lc
        for w in (
            "mouse",
            "trackball",
            "keyboard",
            "headset",
            "headphone",
            "earbud",
            "earbuds",
            "airpod",
            "buds",
            "pods",
            "hs80",
        )
    ):
        return True

    # Common HID/audio service UUIDs for peripherals.
    peripheral_uuids = {
        "00001124-0000-1000-8000-00805f9b34fb",  # HID
        "0000110b-0000-1000-8000-00805f9b34fb",  # Audio Sink
        "0000110e-0000-1000-8000-00805f9b34fb",  # A/V Remote Control
        "0000111e-0000-1000-8000-00805f9b34fb",  # Handsfree
        "0000111f-0000-1000-8000-00805f9b34fb",  # Handsfree Audio Gateway
    }
    uuids_lc = {str(u).lower() for u in (uuids or [])}
    return bool(uuids_lc & peripheral_uuids)


def _build_bt_overrides():
    """
    Build lookup maps from BT_TARGETS:
      by_address["AA:BB:..."] = {"name": ..., "icon": ...}
      by_name["my device name"] = {"name": ..., "icon": ...}
    """
    by_address = {}
    by_name = {}

    icon_aliases = {
        "ICON_MOUSE": ICON_MOUSE,
        "ICON_HEADSET": ICON_HEADSET,
        "ICON_KEYBOARD": ICON_KEYBOARD,
        "ICON_EARBUDS": ICON_EARBUDS,
    }

    bt_targets_local = []
    try:
        if BT_TARGETS_LOCAL_PATH.exists():
            loaded = json.loads(BT_TARGETS_LOCAL_PATH.read_text())
            if isinstance(loaded, list):
                bt_targets_local = loaded
    except Exception:
        bt_targets_local = []

    for item in BT_TARGETS + bt_targets_local:
        if not isinstance(item, dict):
            continue
        address = str(item.get("address", "")).strip().upper()
        name = str(item.get("name", "")).strip()
        icon_raw = item.get("icon", "")
        icon = icon_aliases.get(str(icon_raw).strip(), str(icon_raw).strip())
        row = {
            "name": name,
            "icon": icon,
        }
        if address:
            by_address[address] = row
        if name:
            by_name[name.lower()] = row
    return by_address, by_name


def get_bluez_batteries():
    """Return [(name, icon, pct|None, is_charging:bool)] for BT devices exposing Battery1."""
    results = []
    try:
        import dbus
        bus     = dbus.SystemBus()
        mgr_obj = bus.get_object("org.bluez", "/")
        manager = dbus.Interface(mgr_obj, "org.freedesktop.DBus.ObjectManager")
        objects = manager.GetManagedObjects()

        by_address, by_name = _build_bt_overrides()

        for _path, ifaces in objects.items():
            battery = ifaces.get("org.bluez.Battery1")
            device  = ifaces.get("org.bluez.Device1")
            if device is None:
                continue
            raw_pct = int(battery.get("Percentage", 0)) if battery is not None else 0
            pct     = raw_pct if raw_pct > 0 else None
            name    = str(device.get("Name", "BT Device"))
            addr    = str(device.get("Address", "")).upper()
            connected = bool(device.get("Connected", False))
            uuids = list(device.get("UUIDs", []))

            override = by_address.get(addr) or by_name.get(name.lower())
            include_device = (
                battery is not None
                or (connected and (override is not None or _looks_like_bt_peripheral(name, uuids)))
            )
            if not include_device:
                continue

            if override:
                final_name = override["name"] or name
                final_icon = override["icon"] or _bt_icon(name)
            else:
                final_name = name
                final_icon = _bt_icon(name)

            # BlueZ does not expose a charging property — we can only read level
            results.append((final_name, final_icon, pct, False))
    except Exception:
        pass
    return results


# ── Output helpers ────────────────────────────────────────────────────────────

def _pct_bar(pct, width=8):
    """Unicode block progress bar, e.g.  '██████░░'."""
    filled = round(pct / 100 * width)
    return "█" * filled + "░" * (width - filled)


def _battery_class(pct, is_charging=False):
    if pct is None:
        return "unavailable"
    if is_charging:
        return "charging"
    if pct <= CRITICAL_PCT:
        return "critical"
    if pct <= WARN_PCT:
        return "warning"
    return "normal"


# ── Device cycling (rotate icon every 5 minutes) ──────────────────────────────

def _get_cycle_state_file() -> Path:
    """Return the state file path for tracking which device to show."""
    cache_dir = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
    cache_dir.mkdir(parents=True, exist_ok=True)
    return cache_dir / "waybar-peripheral-battery.json"


def _get_current_device_index(device_count: int) -> int:
    """
    Return the index of the device to display (0 to device_count-1).
    Rotates every 5 minutes (300 seconds).
    """
    if device_count <= 0:
        return 0

    state_file = _get_cycle_state_file()
    CYCLE_INTERVAL = 300  # 5 minutes
    
    try:
        state = json.loads(state_file.read_text())
        last_time = state.get("last_rotation", 0)
        current_idx = state.get("current_index", 0)
    except Exception:
        last_time = 0
        current_idx = 0
    
    now = time.time()
    # Keep saved index valid even if device count changed since last run.
    current_idx = current_idx % device_count

    if now - last_time >= CYCLE_INTERVAL:
        # Time to rotate to the next device
        current_idx = (current_idx + 1) % device_count
        try:
            state_file.write_text(json.dumps({
                "last_rotation": now,
                "current_index": current_idx
            }))
        except Exception:
            pass
    
    return current_idx


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    mode = _output_mode()
    devices = get_evdev_batteries() + get_bluez_batteries()

    if not devices:
        if mode == "icon":
            text = ICON_KEYBOARD
        elif mode == "percent":
            text = "?"
        else:
            text = ICON_KEYBOARD + " ?"
        print(json.dumps({
            "text":    text,
            "stack":   ICON_KEYBOARD + "\n?",
            "alt":     ICON_KEYBOARD + "\n?",
            "tooltip": (
                "No wireless peripheral batteries detected.\n"
                "• Check dongle is plugged in\n"
                "• Ensure you are in the 'input' group:\n"
                "  sudo usermod -aG input $USER  (then re-login)"
            ),
            "class": "unavailable",
        }))
        return

    # Per-device tooltip
    ICON_CHARGING = "\U000F0084"   # 󰂄  nf-md-battery_charging

    name_w = max(len(n) for n, _, _, _ in devices)
    lines  = []
    for name, icon, pct, is_charging in devices:
        if pct is not None:
            charge_icon = f" {ICON_CHARGING}" if is_charging else ""
            pct_str = f"{pct}%{charge_icon}"
            bar     = _pct_bar(pct)
        else:
            pct_str = "—"
            bar     = "░" * 8
        lines.append(f"{icon}  {name:<{name_w}}  {pct_str:>6}  {bar}")

    # Text: rotate through devices that have battery data (skip unknowns like disconnected headsets)
    known_devices = [(n, ic, p, ch) for (n, ic, p, ch) in devices if p is not None]
    if known_devices:
        current_idx = _get_current_device_index(len(known_devices))
        cycled_name, cycled_icon, cycled_pct, cycled_charging = known_devices[current_idx]
    else:
        current_idx = _get_current_device_index(len(devices))
        cycled_name, cycled_icon, cycled_pct, cycled_charging = devices[current_idx]

    if cycled_pct is not None:
        charge_icon = f" {ICON_CHARGING}" if cycled_charging else ""
        pct_text = f"{cycled_pct}%{charge_icon}"
        if mode == "icon":
            text = cycled_icon
        elif mode == "percent":
            text = pct_text
        else:
            text = f"{cycled_icon} {pct_text}"
        stack = f"{cycled_icon}\n{pct_text}"
        worst_class = _battery_class(cycled_pct, cycled_charging)
    else:
        if mode == "icon":
            text = cycled_icon
        elif mode == "percent":
            text = "—"
        else:
            text = f"{cycled_icon} —"
        stack = f"{cycled_icon}\n—"
        worst_class = "unavailable"

    # Overall class: use worst battery (for critical/warning alerts to always show)
    all_known = [(p, ch) for (_, _, p, ch) in devices if p is not None]
    if all_known:
        worst_idx = min(range(len(all_known)), key=lambda i: all_known[i][0])
        worst_pct, worst_charging = all_known[worst_idx]
        overall_class = _battery_class(worst_pct, worst_charging)
    else:
        overall_class = "unavailable"

    print(json.dumps({
        "text":    text,
        "stack":   stack,
        "alt":     stack,
        "tooltip": "\n".join(lines),
        "class":   overall_class,
    }))


if __name__ == "__main__":
    main()
