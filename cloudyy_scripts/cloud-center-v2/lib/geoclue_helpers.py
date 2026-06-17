"""Cloud Center — GeoClue2 helpers for Region & Time page."""
from __future__ import annotations

import logging
import os
import pwd
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger(__name__)

GEOLOCATION_FILE = Path("/etc/geolocation")
STATIC_DROPIN = Path("/etc/geoclue/conf.d/50-cloudyy-static.conf")
ALLOW_DROPIN = Path("/etc/geoclue/conf.d/50-cloudyy-allow-cloud-center.conf")
APPLY_SCRIPT = Path(__file__).resolve().parent / "apply_geolocation.py"


@dataclass
class GeoLocation:
    latitude: float
    longitude: float
    accuracy: float
    altitude: float = 0.0
    source: str = "unknown"


def service_active() -> bool:
    try:
        r = subprocess.run(
            ["systemctl", "is-active", "geoclue"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return r.stdout.strip() == "active"
    except Exception:
        return False


def is_manual_mode() -> bool:
    return GEOLOCATION_FILE.is_file() and STATIC_DROPIN.is_file()


def read_static_geolocation() -> GeoLocation | None:
    if not GEOLOCATION_FILE.is_file():
        return None
    try:
        values: list[float] = []
        for line in GEOLOCATION_FILE.read_text().splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            values.append(float(stripped.split()[0]))
            if len(values) >= 4:
                break
        if len(values) < 2:
            return None
        lat, lon = values[0], values[1]
        alt = values[2] if len(values) > 2 else 0.0
        acc = values[3] if len(values) > 3 else 200.0
        return GeoLocation(lat, lon, acc, alt, "static")
    except Exception as e:
        log.warning("Failed to read /etc/geolocation: %s", e)
        return None


def get_location(timeout: float = 8.0) -> GeoLocation | None:
    static = read_static_geolocation()
    if is_manual_mode() and static is not None:
        return static

    try:
        import gi

        gi.require_version("Geoclue", "2.0")
        from gi.repository import Geoclue

        simple = Geoclue.Simple.new_sync(
            "cloud-center",
            Geoclue.AccuracyLevel.EXACT,
            None,
        )
        loc = simple.get_location()
        if loc is None:
            return static
        return GeoLocation(
            latitude=float(loc.props.latitude),
            longitude=float(loc.props.longitude),
            accuracy=float(loc.props.accuracy),
            altitude=float(loc.props.altitude or 0.0),
            source="geoclue",
        )
    except Exception as e:
        log.warning("GeoClue read failed: %s", e)
        return static


def format_location(loc: GeoLocation | None) -> str:
    if loc is None:
        return "Location unavailable"
    return (
        f"{loc.latitude:.5f}, {loc.longitude:.5f}  "
        f"(±{loc.accuracy:.0f} m, {loc.source})"
    )


def manual_location_pkexec_args(
    latitude: float,
    longitude: float,
    altitude: float = 0.0,
    accuracy: float = 200.0,
) -> list[str]:
    return [
        sys.executable,
        str(APPLY_SCRIPT),
        "--apply",
        "--lat",
        str(latitude),
        "--lon",
        str(longitude),
        "--alt",
        str(altitude),
        "--accuracy",
        str(accuracy),
    ]


def clear_location_pkexec_args() -> list[str]:
    return [sys.executable, str(APPLY_SCRIPT), "--clear"]


def apply_manual_location(
    latitude: float,
    longitude: float,
    altitude: float = 0.0,
    accuracy: float = 200.0,
) -> tuple[bool, str]:
    try:
        r = subprocess.run(
            [
                "pkexec",
                sys.executable,
                str(APPLY_SCRIPT),
                "--apply",
                "--lat",
                str(latitude),
                "--lon",
                str(longitude),
                "--alt",
                str(altitude),
                "--accuracy",
                str(accuracy),
            ],
            env=os.environ.copy(),
            timeout=120,
        )
        if r.returncode == 0:
            return True, "Location applied"
        return False, "Authentication failed or was cancelled"
    except Exception as e:
        return False, str(e)


def clear_manual_location() -> tuple[bool, str]:
    try:
        r = subprocess.run(
            ["pkexec", sys.executable, str(APPLY_SCRIPT), "--clear"],
            env=os.environ.copy(),
            timeout=120,
        )
        if r.returncode == 0:
            return True, "Automatic location restored"
        return False, "Authentication failed or was cancelled"
    except Exception as e:
        return False, str(e)


def geoclue_user() -> str:
    try:
        return pwd.getpwnam("geoclue").pw_name
    except KeyError:
        return "geoclue"
