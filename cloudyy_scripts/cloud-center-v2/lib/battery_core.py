"""GTK-free Battery helpers for Cloud Center."""
from __future__ import annotations

import logging
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Optional

log = logging.getLogger(__name__)

BAT_PATH = Path("/sys/class/power_supply/BAT0")
THRESHOLD_PATH = BAT_PATH / "charge_control_end_threshold"
ASUS_MODE_PATH = Path("/sys/devices/platform/asus-nb-wmi/charge_mode")

ASUS_MODES = ["Balanced", "Full Capacity", "Battery Care"]
ASUS_MODE_DESCS = [
    "Charges to ~80%, suitable for daily use",
    "Charges to 100% for extended sessions",
    "Charges to ~60% for long-term battery health",
]

ALLOWED_ACTIONS = frozenset({"set_threshold", "set_charge_mode"})


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
    energy_wh: float = 0.0
    energy_full_wh: float = 0.0
    energy_full_design_wh: float = 0.0
    energy_rate_w: float = 0.0
    time_remaining_str: str = ""
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


def battery_present(bat_path: Path = BAT_PATH) -> bool:
    return bat_path.is_dir()


def has_threshold(threshold_path: Path = THRESHOLD_PATH) -> bool:
    return threshold_path.exists()


def has_asus_mode(asus_path: Path = ASUS_MODE_PATH) -> bool:
    return asus_path.exists()


def sysfs_int(bat_path: Path, rel: str, default: int = 0) -> int:
    try:
        return int((bat_path / rel).read_text().strip())
    except Exception:
        return default


def sysfs_str(bat_path: Path, rel: str, default: str = "N/A") -> str:
    try:
        value = (bat_path / rel).read_text().strip()
        return value if value else default
    except Exception:
        return default


def parse_upower(info: BatteryInfo) -> None:
    try:
        listed = subprocess.run(
            ["upower", "-e"], capture_output=True, text=True, timeout=5,
        )
        if listed.returncode != 0:
            return
        bat = next(
            (line.strip() for line in listed.stdout.splitlines() if "BAT" in line),
            None,
        )
        if not bat:
            return
        detail = subprocess.run(
            ["upower", "-i", bat], capture_output=True, text=True, timeout=5,
        )
        if detail.returncode != 0:
            return
        for line in detail.stdout.splitlines():
            key, _, value = line.strip().partition(":")
            key = key.strip()
            value = value.strip()
            if key == "energy" and "Wh" in value:
                info.energy_wh = float(value.split()[0])
            elif key == "energy-full" and "Wh" in value:
                info.energy_full_wh = float(value.split()[0])
            elif key == "energy-full-design" and "Wh" in value:
                info.energy_full_design_wh = float(value.split()[0])
            elif key == "energy-rate" and "W" in value:
                info.energy_rate_w = float(value.split()[0])
            elif key == "time to full":
                info.time_remaining_str = f"{value} to full"
            elif key == "time to empty":
                info.time_remaining_str = f"{value} to empty"
    except Exception as exc:
        log.debug("upower parse error: %s", exc)


def capacity_str(info: BatteryInfo) -> str:
    if info.energy_full_wh > 0:
        return f"{info.energy_wh:.1f} / {info.energy_full_wh:.1f} Wh"
    if info.charge_full_uah > 0 and info.voltage_v > 0:
        full = (info.charge_full_uah / 1e6) * info.voltage_v
        design = (info.charge_full_design_uah / 1e6) * info.voltage_v
        return f"{full:.1f} / {design:.1f} Wh (est.)"
    return "—"


def status_icon_name(info: BatteryInfo) -> str:
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


def write_sysfs(path: Path, value: str) -> bool:
    try:
        path.write_text(value)
        return True
    except PermissionError:
        pass
    try:
        result = subprocess.run(
            ["pkexec", "tee", str(path)],
            input=value,
            capture_output=True,
            text=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False


def read_battery_info(
    *,
    bat_path: Path = BAT_PATH,
    threshold_path: Path = THRESHOLD_PATH,
    asus_path: Path = ASUS_MODE_PATH,
    upower: bool = True,
) -> BatteryInfo:
    threshold_ok = threshold_path.exists()
    info = BatteryInfo(
        percentage=sysfs_int(bat_path, "capacity"),
        status=sysfs_str(bat_path, "status"),
        voltage_uv=sysfs_int(bat_path, "voltage_now"),
        current_ua=sysfs_int(bat_path, "current_now"),
        charge_full_uah=sysfs_int(bat_path, "charge_full"),
        charge_full_design_uah=sysfs_int(bat_path, "charge_full_design"),
        cycle_count=sysfs_int(bat_path, "cycle_count"),
        manufacturer=sysfs_str(bat_path, "manufacturer"),
        model=sysfs_str(bat_path, "model_name"),
        technology=sysfs_str(bat_path, "technology"),
        serial=sysfs_str(bat_path, "serial_number"),
        charge_end_threshold=(
            sysfs_int(bat_path, "charge_control_end_threshold", 100)
            if threshold_ok else 100
        ),
    )
    if upower:
        parse_upower(info)
    if asus_path.exists():
        try:
            info.charge_mode = int(asus_path.read_text().strip())
        except Exception:
            info.charge_mode = None
    return info


def build_battery_snapshot(
    *,
    bat_path: Path = BAT_PATH,
    threshold_path: Path = THRESHOLD_PATH,
    asus_path: Path = ASUS_MODE_PATH,
    upower: bool = True,
) -> dict[str, Any]:
    present = battery_present(bat_path)
    capabilities = {
        "threshold": threshold_path.exists() if present else False,
        "asus_mode": asus_path.exists() if present else False,
    }
    if not present:
        return {
            "present": False,
            "capabilities": capabilities,
            "info": None,
            "display": {
                "percentage_label": "—",
                "power_label": "—",
                "time_label": "—",
                "health_label": "—",
                "capacity_label": "—",
                "voltage_label": "—",
                "cycles_label": "N/A",
                "icon": "battery-missing-symbolic",
            },
            "asus_modes": list(ASUS_MODES),
            "asus_mode_descriptions": list(ASUS_MODE_DESCS),
            "error": "",
        }

    info = read_battery_info(
        bat_path=bat_path,
        threshold_path=threshold_path,
        asus_path=asus_path,
        upower=upower,
    )
    payload = asdict(info)
    payload["voltage_v"] = info.voltage_v
    payload["power_w"] = info.power_w
    payload["health_pct"] = info.health_pct
    return {
        "present": True,
        "capabilities": capabilities,
        "info": payload,
        "display": {
            "percentage_label": f"{info.percentage}%",
            "power_label": (
                f"{info.power_w:.2f} W" if info.power_w > 0.01 else "—"
            ),
            "time_label": info.time_remaining_str or "—",
            "health_label": (
                f"{info.health_pct:.1f}%" if info.health_pct > 0 else "—"
            ),
            "capacity_label": capacity_str(info),
            "voltage_label": (
                f"{info.voltage_v:.3f} V" if info.voltage_v > 0 else "—"
            ),
            "cycles_label": (
                str(info.cycle_count) if info.cycle_count > 0 else "N/A"
            ),
            "icon": status_icon_name(info),
            "hero_title": f"Battery — {info.status}",
            "hero_subtitle": (
                f"{info.power_w:.1f} W" if info.power_w > 0.01 else ""
            ),
        },
        "asus_modes": list(ASUS_MODES),
        "asus_mode_descriptions": list(ASUS_MODE_DESCS),
        "error": "",
    }


def set_charge_threshold(
    value: int,
    *,
    threshold_path: Path = THRESHOLD_PATH,
) -> dict[str, Any]:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError("threshold must be an integer")
    if value < 40 or value > 100:
        raise ValueError("threshold must be between 40 and 100")
    if not threshold_path.exists():
        return {"ok": False, "message": "Charge limit is not available"}
    ok = write_sysfs(threshold_path, str(value))
    return {
        "ok": ok,
        "message": (
            f"Charge limit set to {value}%"
            if ok
            else "Failed to set charge limit — permission denied"
        ),
        "value": value,
    }


def set_charge_mode(
    mode: int,
    *,
    asus_path: Path = ASUS_MODE_PATH,
) -> dict[str, Any]:
    if not isinstance(mode, int) or isinstance(mode, bool):
        raise ValueError("charge mode must be an integer")
    if mode < 0 or mode >= len(ASUS_MODES):
        raise ValueError("charge mode out of range")
    if not asus_path.exists():
        return {"ok": False, "message": "Charge mode is not available"}
    ok = write_sysfs(asus_path, str(mode))
    label = ASUS_MODES[mode]
    return {
        "ok": ok,
        "message": (
            f"Charge mode set to {label}"
            if ok
            else "Failed to set charge mode — permission denied"
        ),
        "value": mode,
    }


def run_battery_action(
    action: str,
    value: Any,
    *,
    threshold_path: Path = THRESHOLD_PATH,
    asus_path: Path = ASUS_MODE_PATH,
) -> dict[str, Any]:
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"unknown battery action: {action}")
    if action == "set_threshold":
        return set_charge_threshold(int(value), threshold_path=threshold_path)
    return set_charge_mode(int(value), asus_path=asus_path)
