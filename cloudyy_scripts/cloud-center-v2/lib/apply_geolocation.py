#!/usr/bin/env python3
"""Apply or clear Cloud Center static GeoClue location (run via pkexec)."""
from __future__ import annotations

import argparse
import os
import pwd
import subprocess
import sys
from pathlib import Path

GEOLOCATION_FILE = Path("/etc/geolocation")
CONF_DIR = Path("/etc/geoclue/conf.d")
STATIC_DROPIN = CONF_DIR / "50-cloudyy-static.conf"
ALLOW_DROPIN = CONF_DIR / "50-cloudyy-allow-cloud-center.conf"

STATIC_CONF = """# Cloud Center — static geolocation source
[wifi]
enable=false

[3g]
enable=false

[cdma]
enable=false

[modem-gps]
enable=false

[network-nmea]
enable=false

[ip]
enable=false

[static-source]
enable=true
"""

ALLOW_CONF = """[cloud-center]
allowed=true
system=false
users=
"""


def _geoclue_uid_gid() -> tuple[int, int]:
    try:
        entry = pwd.getpwnam("geoclue")
        return entry.pw_uid, entry.pw_gid
    except KeyError:
        return os.getuid(), os.getgid()


def _restart_geoclue() -> None:
    subprocess.run(["systemctl", "restart", "geoclue"], check=True)


def apply_location(lat: float, lon: float, alt: float, accuracy: float) -> None:
    if not os.geteuid() == 0:
        print("This script must run as root (use pkexec).", file=sys.stderr)
        sys.exit(1)

    GEOLOCATION_FILE.write_text(f"{lat}\n{lon}\n{alt}\n{accuracy}\n")
    uid, gid = _geoclue_uid_gid()
    os.chown(GEOLOCATION_FILE, uid, gid)
    os.chmod(GEOLOCATION_FILE, 0o600)

    CONF_DIR.mkdir(parents=True, exist_ok=True)
    STATIC_DROPIN.write_text(STATIC_CONF)
    ALLOW_DROPIN.write_text(ALLOW_CONF)

    _restart_geoclue()
    print(f"Static location set to {lat}, {lon}")


def clear_location() -> None:
    if not os.geteuid() == 0:
        print("This script must run as root (use pkexec).", file=sys.stderr)
        sys.exit(1)

    if GEOLOCATION_FILE.exists():
        GEOLOCATION_FILE.unlink()
    if STATIC_DROPIN.exists():
        STATIC_DROPIN.unlink()

    _restart_geoclue()
    print("Automatic GeoClue sources restored")


def main() -> None:
    parser = argparse.ArgumentParser(description="Cloud Center GeoClue location helper")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apply", action="store_true", help="Set static location")
    group.add_argument("--clear", action="store_true", help="Remove static location")
    parser.add_argument("--lat", type=float, default=0.0)
    parser.add_argument("--lon", type=float, default=0.0)
    parser.add_argument("--alt", type=float, default=0.0)
    parser.add_argument("--accuracy", type=float, default=200.0)
    args = parser.parse_args()

    try:
        if args.apply:
            apply_location(args.lat, args.lon, args.alt, args.accuracy)
        else:
            clear_location()
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {e}", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
